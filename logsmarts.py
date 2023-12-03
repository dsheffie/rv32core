#!/usr/bin/python3

import subprocess
import re
import sys
import math
import numpy as np 
import scipy.stats as st

import glob

def main():
    ipc_samples = []
    all_samples = []            
    with open(sys.argv[1], 'r') as f:
        for line in f:
            all_samples.append(float(line))

    print('read %d samples' % len(all_samples))

    sz = 32
    for i in range(sz, len(all_samples), sz):
        cpi = all_samples[i]
        ipc_samples.append(cpi)

    print('%d subsamples' % len(ipc_samples))
    ipc_samples.sort()

    print('max %g, min %g ipc' % (1.0/ipc_samples[0], 1.0/ipc_samples[len(ipc_samples)-1]))
    print('median %g ipc' % (1.0/ipc_samples[len(ipc_samples)//2]))
    
    mean = np.mean(ipc_samples)
    var = np.std(ipc_samples)
    coeff_var = var/mean
    
    print('cpi %g mean, %g stdvar, %g coeff var' % (mean,var,coeff_var))
    confid = st.norm.interval(alpha=0.99,  loc=np.mean(ipc_samples), scale=st.sem(ipc_samples))

    z = 3
    d = (z*coeff_var*mean)/math.sqrt(len(ipc_samples))
    print('99.7 confidence is %g to %g ipc (error %g percent)' % (1.0/(mean-d),1/(mean+d),100.0*(d/mean)))

    
if __name__ == '__main__':
    main()
