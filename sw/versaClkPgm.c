#include <stdio.h>
#include <ecur.h>
#include <getopt.h>
#include <inttypes.h>
#include <string.h>
#include <math.h>

#define I2C_BASE 0x100000
#define CLK_SLA  0x6a
#define CLK_MUX  0x1

static void usage(const char *nm)
{
    fprintf(stderr, "usage: %s [-h] [-a <dst_ip>] [-f clock frequency]\n", nm);
    fprintf(stderr, "       -h                       : this message\n");
    fprintf(stderr, "       -a dst_ip                : set target ip (dot notation). Can also be defined by\n");
    fprintf(stderr, "                                  the 'ECUR_TARGET_IP' environment variable\n");
    fprintf(stderr, "       -D output divider        : output divider\n");
    fprintf(stderr, "       -f frequency             : desired output frequency (in Hz)\n");
  
}

static int64_t
i2cReadFromPage( Ecur e, uint8_t sla, uint8_t mux, uint8_t off, unsigned l )
{
unsigned i;
int      st;
uint8_t  buf[8];
uint64_t rv = 0;
uint32_t addr;

	addr = I2C_BASE + ((sla & 0x7f) << 12) + ((mux & 0xf) << 8) + off;

	if ( l > 7 ) {
		fprintf(stderr, "Internal error: i2cRead supports max. length of 7\n");
		return -1;
	}
	st = ecurRead8( e, addr, buf, l );
	if ( st < 0 ) {
		fprintf(stderr, "ecurRead8() failed (%d)\n", st);
		return -1;
	}

	rv = 0;
	for ( i = 0; i < l; i++ ) {
		rv = (rv << 8 ) | buf[i];
	}
	return rv;
}

static int
i2cWriteToPage( Ecur e, uint8_t sla, uint8_t mux, uint8_t off, uint64_t val, unsigned l )
{
int      i;
int      st;
uint8_t  buf[8];
uint32_t addr;

	addr = I2C_BASE + ((sla & 0x7f) << 12) + ((mux & 0xf) << 8) + off;

	if ( l > 7 ) {
		fprintf(stderr, "Internal error: i2cRead supports max. length of 7\n");
		return -1;
	}

	for ( i = l - 1; i >= 0; i-- ) {
		buf[i] = (val & 0xff);
		val  >>= 8;
	}

	st = ecurWrite8( e, addr, buf, l );
	if ( st < 0 ) {
		fprintf(stderr, "ecurWrite8() failed (%d)\n", st);
		return -1;
	}
	return st;
}


static void
pdiv(FILE *f, const char *pre, uint64_t d_i, uint64_t d_f, unsigned nrm)
{
int      l = strlen( pre );
/* can hold max length of a uint64 in decimal base */
char     bar[24];
unsigned w;
uint64_t p10;
double   d = d_i + (double)d_f/(double)(1ULL<<nrm);

	bar[0] = '-';
	for ( w = 1, p10 = 10; d_f >= p10; w++ ) {
		bar[w] = '-';
		p10   *= 10;
	}
	bar[w] = 0;

	if ( 0 == d_f ) {
		fprintf(f, "%s: %" PRId64 "\n", pre, d_i);
	} else {
		fprintf(f, "%*s         %*" PRId64 "\n", l, "", w, d_f);
		fprintf(f, "%s: %4" PRId64 " + %s = %g\n", pre, d_i, bar, d);
		fprintf(f, "%*s       %*s2^%d\n",     l,"", w/2, "",nrm);
	}
}

static double reg2C(uint8_t reg)
{
double c;
	/* The  VC6-RegProgramming manual gives different values from
	 * the 5p59v6925 datasheet:
	 *    VC6-RegProgramming says that the tunable capacitance
	 *      CTUNE = XTAL[0] * 0x43 + XTAL[4:1] * 0.43 pF
     * whereas the datasheet says:
     *      CTUNE = 0.5pF * XTAL[4:0] and Ci = CTUNE + 9pF
	 * the RegProgramming manual does not elaborate on a fixed/base
	 * capacitance value.
	 * However: tests showed that toggling XTAL[0] had the same effect
	 * as toggling XTAL[1] which hints at the RegProgramming manual
	 * being correct!
	 */
	c = 0.0;
	if ( !! (reg & 4) ) {
		c += 0.43;
	}
	c += 0.43 * (reg>>3);
	return c;
}

int
main(int argc, char **argv)
{
int         opt;
int         rval   = 1;
const char *optstr = "ha:D:f:";
const char *dip    = 0;
Ecur        e      = 0;
uint16_t    dprt   = 4096;
double      fref   = 25.0E6;
int         verb   = 0;
uint32_t    dsel   = (uint32_t)-1;
uint32_t   *u32_p;
double     *d_p;
int64_t     d_i;
int64_t     d_f;
double      fbDiv;
double      fVCO;
double      outDiv;
double      fDes = 0.0;
char        fmt[256];
uint64_t    outDiv_ibits;
uint64_t    outDiv_fbits;

   while ( (opt = getopt(argc, argv, optstr)) > 0 ) {
        u32_p = 0;
		d_p   = 0;
        switch ( opt ) {
			case 'a':
				dip = optarg;
				break;
			case 'f':
				d_p = &fDes;
				break;
            case 'h':
                rval = 0;
				/* fall through */
            default:
                usage( argv[0] );
                goto bail;
			case 'D':
				u32_p = &dsel;
				break;
		}
        if ( u32_p && ( 1 != sscanf(optarg, "%" SCNi32, u32_p) ) ) {
            fprintf(stderr, "Error: Unable to scan argument to option %d\n", opt);
            goto bail;
        }
        if ( d_p && ( 1 != sscanf(optarg, "%lg", d_p) ) ) {
            fprintf(stderr, "Error: Unable to scan argument to option %d\n", opt);
            goto bail;
        }
	}

	if ( dsel < 1 || dsel > 4 ) {
		fprintf(stderr, "Invalid output divider selection (1..4); please use -D <divider>\n");
		goto bail;
	}

    if ( ! (e = ecurOpen( dip, dprt, verb )) ) {
        fprintf(stderr, "Unable to connect to Firmware at %s:%" PRIu16 "\n", dip, dprt);
        goto bail;
    }

	d_i = i2cReadFromPage( e, CLK_SLA, CLK_MUX, 0x17, 5 );
	if ( d_i < 0 ) {
		goto bail;
	}
	d_f = (d_i & ( (1 << 24) - 1 ) );
	d_i = d_i >> (24 + 4);

	fbDiv = d_i + (double)d_f/(double)(1<<24);

	pdiv(stdout, "Feedback Divider", d_i, d_f, 24 );

	fVCO = fref * fbDiv;
	printf("Frequency @VCO  : %#.8lg MHz\n", fVCO/1.0E6);
	
	d_i = i2cReadFromPage( e, CLK_SLA, CLK_MUX, 0x1D + (dsel<<4), 2 );
	if ( d_i < 0 ) {
		goto bail;
	}
	outDiv_ibits = (d_i & 0xf);
	d_i >>= 4;

	d_f = i2cReadFromPage( e, CLK_SLA, CLK_MUX, 0x12 + (dsel<<4), 4 );
	if ( d_f < 0 ) {
		goto bail;
	}
	outDiv_fbits = (d_f & 0x3);
	d_f >>= 2;

	outDiv = (double)d_i + (double)d_f/(double)(1ULL<<24);

	if ( 0.0 == fDes ) {
		snprintf(fmt, sizeof(fmt), "Output Divider %d", dsel);

		pdiv(stdout, fmt, d_i, d_f, 24);

		/* Don't show 'old' value when writing new freq. */
		printf("Frequency @Out %d: %#.8lg MHz\n", dsel, fVCO/outDiv/2.0/1.0E6);

		/* Crystal load */
		d_f = i2cReadFromPage( e, CLK_SLA, CLK_MUX, 0x12, 2 );
		if ( d_f < 0 ) {
			goto bail;
		}
		printf("Crystal Load    : X1 %.3f pF, X2 %.3f pF\n", reg2C(d_f >> 8), reg2C(d_f));
	} else {
		/* Set new freq. */
		if ( fDes < 0.0 ) {
			fprintf(stderr, "Illegal output frequency (<0)\n");
			goto bail;
		}
		if ( fDes > 350.0E6 ) {
			fprintf(stderr, "Desired output freq. too high - not supported by 5p49v6825\n");
			goto bail;
		}
		outDiv = fVCO/2.0/fDes;
		if ( outDiv > (double)0xfff ) {
			fprintf(stderr, "Desired output freq. too low - must cascade FODs (not implemented)\n");
			goto bail;
		}
		d_i = (uint64_t)floor(outDiv);
		d_f = (uint64_t)round( (outDiv - floor(outDiv)) * (double)(1ULL<<24) );
		if ( d_f > 0xffffff ) {
			d_f = 0xffffff;
		}

		d_i = (d_i<<4) | outDiv_ibits;
		d_f = (d_f<<2) | outDiv_fbits;

		if ( i2cWriteToPage( e, CLK_SLA, CLK_MUX, 0x1D + (dsel<<4), d_i, 2 ) < 0 ) {
			fprintf( stderr, "Writing integer part of output divider failed; CLOCK MAY BE ILL-PROGRAMMED\n");
			goto bail;
		}

		if ( i2cWriteToPage( e, CLK_SLA, CLK_MUX, 0x12 + (dsel<<4), d_f, 4 ) < 0 ) {
			fprintf( stderr, "Writing fractional part of output divider failed; CLOCK MAY BE ILL-PROGRAMMED\n");
			goto bail;
		}
	}

	rval = 0;
bail:
    if ( e ) {
        ecurClose( e );
    }
	return rval;
}
