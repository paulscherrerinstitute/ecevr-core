#!/usr/bin/env bash
od -Ad -tx1 -w1 -v eeprom_config_tst.sii  | awk 'END{printf("      others => x\"ff\"\n");}{if (NF > 1) { printf("      %d => x\"%s\",\n", $1, $2); }}'
