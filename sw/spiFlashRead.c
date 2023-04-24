#include <stdio.h>
#include <inttypes.h>
#include <ecur.h>
#include <getopt.h>
#include <string.h>
#include <errno.h>

#define DFLT_BASE 0x080000
#define DFLT_ADDR 0
#define DFLT_LENG 4

static void usage( const char * nm )
{
	fprintf(stderr, "Usage: %s [-hv] -a <ip_addr> [-m SPI memory start] [-l SPI memory length] [-b SPI controller base addr]\n", nm);
	fprintf(stderr, "\n");
	fprintf(stderr, "Utility for reading SPI flash contents on the target via EoE/ECUR\n");
	fprintf(stderr, "Note: the result is written to <stdout> in binary\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "    -a <ip_addr> : target IP (may also be set via ECUR_TARGET_IP env-var)\n");
	fprintf(stderr, "    -b <addr>    : SPI controller base address (default: 0x%06x)\n", DFLT_BASE);
	fprintf(stderr, "    -m <addr>    : SPI memory range start address (default: 0x%08x)\n", DFLT_ADDR);
	fprintf(stderr, "    -l <len>     : SPI memory range length (default: 0x%08x)\n", DFLT_LENG);
	fprintf(stderr, "    -h           : this message\n");
	fprintf(stderr, "    -v           : increase verbosity\n");
}

#define BURST_COUNT 256
#define BURST_SIZE  (BURST_COUNT * sizeof( uint32_t ) )

#define LD_PAGE_SZ 16
#define PAGE_SIZE  (1<<LD_PAGE_SZ)
#define PAGE_MASK  (PAGE_SIZE - 1)

#define PAGE_REG 0x10000

static uint32_t pageNo(uint32_t addr)
{
	return addr >> LD_PAGE_SZ;
}

static uint32_t inPage(uint32_t base, uint32_t addr)
{
	return base + ( addr & PAGE_MASK );
}

static int
setPage( Ecur e, uint32_t bas, uint32_t addr )
{
uint32_t pg = pageNo( addr );
	return ecurQWrite32( e, bas + PAGE_REG, &pg, 1 );
}

int
main(int argc, char **argv)
{
/* memory area in SPI */
uint32_t      addr   = DFLT_ADDR;
uint32_t      len    = DFLT_LENG;
/* controller base address */
uint32_t      base   = DFLT_BASE;
const char   *ipAddr = NULL;
unsigned      port   = 4096;
uint32_t     *u_p;
unsigned      verb   = 0;
int           opt;
Ecur          e      = NULL;
int           rv     = 1;
uint8_t       buf[BURST_SIZE];
unsigned      bufLen;
uint32_t      thePage, newPage;
uint32_t      newAddr;
uint32_t      tail;

	while ( ( opt = getopt( argc, argv, "a:b:m:l:hv" ) ) > 0 ) {
		u_p = NULL;
		switch ( opt ) {
            default:  fprintf( stderr, "Unknown option -%c\n", opt );
			/* fall thru */
			case 'h': usage( argv[0] ); return 0;
			case 'm': u_p = &addr;      break; 
			case 'l': u_p = &len;       break; 
			case 'a': ipAddr = optarg;  break;
            case 'b': u_p = &base;      break;
			case 'v': verb++;           break;
		}
		if ( u_p && 1 != sscanf(optarg, "%" SCNi32, u_p) ) {
			fprintf( stderr, "Unable to scan argument of -%c\n", opt );
		}
	}

	if ( ! (e = ecurOpen( ipAddr, port, verb )) ) {
		goto bail;
	}

	thePage = pageNo( addr );
	if ( setPage( e, base, addr ) ) {
		goto bail;
	}

	/* Misaligned head ? */
    bufLen = 0;
	while ( (addr & 3) && (len > bufLen ) ) {
		bufLen++;
        addr++;
	}
	/* readjust */
	addr -= bufLen;

	if ( bufLen > 0 ) {
		if ( ecurQRead8(e, inPage( base, addr ), buf, bufLen, NULL, NULL) ) {
			goto bail;
		}
	    addr += bufLen;
	   	len  += bufLen;
		if ( (newPage = pageNo( addr )) != thePage ) {
			thePage = newPage;
			if ( setPage( e, base, addr ) ) {
				goto bail;
			}
		}
	}

	if ( ecurExecute( e ) < 0 ) {
		goto bail;
	}

	if ( ( bufLen > 0 ) && ( fwrite( buf, sizeof(uint8_t), bufLen, stdout ) != bufLen ) ) {
		fprintf( stderr, "Unable to write output data : %s\n", strerror( errno ) );
		goto bail;
	}

	/* misaligned End ? */
	tail = len & (sizeof(uint32_t) - 1);
	len -= tail;

	while ( len > 0 ) {
		bufLen  = len > BURST_SIZE ? BURST_SIZE : len;
        /* next page boundary */
		newAddr  = (addr & ~PAGE_MASK) + PAGE_SIZE;
		if ( bufLen > newAddr - addr ) {
			bufLen = newAddr - addr;
		}
		if ( ecurQRead32(e, inPage( base, addr ), (uint32_t*)buf, bufLen >> 2, NULL, NULL) ) {
			goto bail;
		}
		if ( ecurExecute( e ) < 0 ) {
			goto bail;
		}
		if ( fwrite( buf, sizeof(uint8_t), bufLen, stdout ) != bufLen ) {
			fprintf( stderr, "Unable to write output data : %s\n", strerror( errno ) );
			goto bail;
		}

		addr += bufLen;
		len  -= bufLen;

		if ( (newPage = pageNo( addr )) != thePage ) {
			thePage = newPage;
			if ( setPage( e, base, addr ) ) {
				goto bail;
			}
			if ( ecurExecute( e ) < 0 ) {
				goto bail;
			}
		}
	}

	if ( tail ) {
		if ( ecurQRead8(e, inPage( base, addr ), buf, tail, NULL, NULL ) ) {
			goto bail;
		}
	}

	rv = 0;
bail:
	if ( rv ) {
		fprintf( stderr, "Errors were encountered -- '-v' may provide more details\n" );
	}
	if ( e ) {
		ecurClose( e );
	}

	return rv;
}
