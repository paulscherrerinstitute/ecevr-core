ECUR_DIR=../../lan9254-rtl-esc/sw
CFLAGS=-O2 -Wall -g -I. $(addprefix -I,$(ECUR_DIR))
LDFLAGS=$(addprefix -L,$(ECUR_DIR)) -lecur

all: ecurcli spiFlashRead versaClkPgm

spiFlashRead.o versaClkPgm.o ecurcli.o:%.o:%.c $(addsuffix /ecur.h,$(ECUR_DIR))
	$(CC) $(CFLAGS) -c $<

ecurcli: ecurcli.o $(addsuffix /libecur.a,$(ECUR_DIR))
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

spiFlashRead: spiFlashRead.o $(addsuffix /libecur.a,$(ECUR_DIR))
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

versaClkPgm: versaClkPgm.o $(addsuffix /libecur.a,$(ECUR_DIR))
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS) -lm

clean:
	$(RM) ecurcli.o spiFlashRead.o ecurcli spiFlashRead versaClkPgm versaClkPgm.o

.PHONY: clean
