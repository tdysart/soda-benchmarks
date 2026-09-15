#!/bin/bash

# This file is supposed to be executed after bambu targeting a openroad device

cp ${SCRIPT_DIR}/to_copy/${PLATFORM}_config.mk ${BAMBUDIR}/config.mk
sed -i.bak "s/kernelname/${KERNELNAME}/g" ${BAMBUDIR}/config.mk && rm -f ${BAMBUDIR}/config.mk.bak
cp ${SCRIPT_DIR}/to_copy/synthesize_Synthesis_kernelname.sh ${BAMBUDIR}/synthesize_Synthesis_${KERNELNAME}.sh
sed -i.bak "s/platformname/${PLATFORM}/g" ${BAMBUDIR}/synthesize_Synthesis_${KERNELNAME}.sh && rm -f ${BAMBUDIR}/synthesize_Synthesis_${KERNELNAME}.sh.bak
cp ${SCRIPT_DIR}/to_copy/${PLATFORM}_constraints.sdc ${BAMBUDIR}/HLS_output/Synthesis/${PLATFORM}_constraints.sdc
sed -i.bak "s/kernelname/${KERNELNAME}/g" ${BAMBUDIR}/HLS_output/Synthesis/${PLATFORM}_constraints.sdc && rm -f ${BAMBUDIR}/HLS_output/Synthesis/${PLATFORM}_constraints.sdc.bak
