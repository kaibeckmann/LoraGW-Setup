#!/usr/bin/python
# **********************************************************************************
# monitor-sensors.py
# **********************************************************************************
# Script for monitoring LoraWAN Gateways based on small Linux computers
# reads sensors connected to the gateway, activates heating element if it's to 
# cold
#
# based on monitor-gpio.py script by Charles-Henri Hallard http://ch2i.eu
#
#
# **********************************************************************************

import RPi.GPIO as GPIO
import thread
import time
import os
import urllib
import sys
import signal
import subprocess
import smbus2
import bme280

i2c_port = 3

bme280_interior_addr = 0x77
bme280_outside_addr  = 0x76

gpio_heating = 18

w1-temp-sensor-case = "28-01156351aeff"

logFilePath = "/home/loragw/data_log.csv"


internet = False # True if internet connected
lorawan  = False # True if local LoraWan server is running
web      = False # True if local Web Server is running
hostapd  = False # True if wifi access point is started
pktfwd   = False # True if packet forwarder is started


def signal_handler(signal, frame):
    GPIO.output(gpio_heating, GPIO.LOW)
    file.close()
    sys.exit(0)


def check_process(process):
  proc = subprocess.Popen(["if pgrep " + process + " >/dev/null 2>&1; then echo '1'; else echo '0'; fi"], stdout=subprocess.PIPE, shell=True)
  (ret, err) = proc.communicate()
  ret = int(ret)
#  print ret
  if ret==1:
    return True
  else:
    return False

def check_inet(delay):
  global internet
  global lorawan
  global web
  global hostapd
  global pktfwd

  while True:
    #print "check Internet"
    try:
      url = "https://www.google.com"
      urllib.urlopen(url)
      internet = True
    except:
      internet = False

    try:
      url = "http://127.0.0.1"
      urllib.urlopen(url)
      web = True
    except:
      web = False

    try:
      url = "http://127.0.0.1:8080"
      urllib.urlopen(url)
      lorawan = True
    except:
      lorawan = False

    # Check WiFi AP mode and packet forwarder
    #hostapd = check_process("hostapd")
    pktfwd = check_process("mp_pkt_fwd") or check_process("poly_pkt_fwd")

    time.sleep(delay)
# END check_inet

# Use the Broadcom SOC Pin numbers
GPIO.setwarnings(False)
GPIO.setmode(GPIO.BCM)
GPIO.setup(gpio_heating, GPIO.OUT)

signal.signal(signal.SIGINT, signal_handler)

try:
   thread.start_new_thread( check_inet, (5, ) )
except:
   print "Error: unable to start thread"

i2c_bus = smbus2.SMBus(i2c_port)

bme280_interior_cal_params = bme280.load_calibration_params(bus, 
        bme280_interior_addr)
bme280_outside_cal_params = bme280.load_calibration_params(bus, 
        bme280_outside_addr)

file = open(logFilePath, "a")

# first open, write header
if os.stat(logFilePath).st_size == 0:
    file.write("#time,temp case,temp int,hum int,pressure int,temp out, hum out, 
    pressure out\n")

# Now wait!
while 1:

    now = datetime.now()

    data_line = ""
    # write time
    data_line += (str(now))
    data_line += ','

    # 1-wire temp sensor

    file_temp = open('/sys/bus/w1/devices/' + str(w1-temp-sensor-case) + 
            '/w1_slave')
    filecontent = file_temp.read()
    file_temp.close()

    stringvalue = filecontent.split("\n")[1].split(" ")[9]
    temperature = float(stringvalue[2:]) / 1000
    
    data_line += '{:6.3f}'.format(temperature)
    data_line += ','


    # i2c BME280 Sensor interior
    data= bme280.sample(i2c_bus, bme280_interior_addr, 
            bme280_interior_cal_params)

    data_line += '{:6.3f},{:5.2f},{6:2f},'.format(data.temperature, 
            data.humidity, data.pressure)

    # i2c BME280 Sensor outside

    data = bme280.sample(i2c_bus, bme280_outside_addr, 
            bme280_outside_cal_params)

    data_line += '{:6.3f},{:5.2f},{6:2f}'.format(data.temperature, 
            data.humidity, data.pressure)

    file.write(data_line + "\n")
    file.flush()
    file.close()

    time.sleep(60)


