#!/usr/bin/env python3
"""System sampler for the frame-rate experiment: once a second the NVIDIA GPU (SM and memory clock, power, temperature, utilisation, P-state, throttle-reason bits)
and the CPU (average and maximum core frequency, hottest thermal zone, total utilisation) to a CSV until it is killed.  usage: sys_sampler.py out.csv"""
import glob
import subprocess
import sys
import time

out = sys.argv[1]
f = open(out, "w")
f.write("t_s,gpu_sm_mhz,gpu_mem_mhz,gpu_w,gpu_c,gpu_util,gpu_mem_util,pstate,throttle,cpu_avg_mhz,cpu_max_mhz,cpu_c,cpu_util\n")
t0 = time.time()


def cpu_times():
    v = [float(x) for x in open("/proc/stat").readline().split()[1:]]
    return sum(v), v[3] + v[4]


last_total, last_idle = cpu_times()
while True:
    try:
        g = subprocess.run(["nvidia-smi", "--query-gpu=clocks.sm,clocks.mem,power.draw,temperature.gpu,utilization.gpu,utilization.memory,pstate,clocks_throttle_reasons.active",
                            "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=5).stdout.strip().split(", ")
    except Exception:
        g = ["", "", "", "", "", "", "", ""]
    freqs = []
    for p in glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq"):
        try:
            freqs.append(int(open(p).read()) / 1000.0)
        except Exception:
            pass
    temps = []
    for p in glob.glob("/sys/class/thermal/thermal_zone*/temp"):
        try:
            temps.append(int(open(p).read()) / 1000.0)
        except Exception:
            pass
    total, idle = cpu_times()
    util = 100.0 * (1.0 - (idle - last_idle) / max(total - last_total, 1.0))
    last_total, last_idle = total, idle
    f.write("%.1f,%s,%.0f,%.0f,%.1f,%s\n" % (time.time() - t0, ",".join(g), sum(freqs) / max(len(freqs), 1), max(freqs or [0]), max(temps or [0]), util))
    f.flush()
    time.sleep(1.0)
