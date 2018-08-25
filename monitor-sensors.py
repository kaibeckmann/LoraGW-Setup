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

gpio_heating = 18


internet = False # True if internet connected
lorawan  = False # True if local LoraWan server is running
web      = False # True if local Web Server is running
hostapd  = False # True if wifi access point is started
pktfwd   = False # True if packet forwarder is started


def signal_handler(signal, frame):
    GPIO.output(gpio_heating, GPIO.LOW)
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

# Use the Broadcom SOC Pin numbers
GPIO.setwarnings(False)
GPIO.setmode(GPIO.BCM)
GPIO.setup(gpio_heating, GPIO.OUT)

signal.signal(signal.SIGINT, signal_handler)

try:
   thread.start_new_thread( check_inet, (5, ) )
except:
   print "Error: unable to start thread"

# Now wait!
while 1:
    led_blu = GPIO.LOW
    led_yel = GPIO.LOW
    led_red = GPIO.LOW
    led_grn = GPIO.LOW

    if internet == True:
      led_blu = GPIO.HIGH
    else:
      led_red = GPIO.HIGH

    if web == True:
      led_yel = GPIO.HIGH
    else:
      led_red = GPIO.HIGH

    if pktfwd == True:
      led_grn = GPIO.HIGH
    else:
      led_red = GPIO.HIGH

    time.sleep(10)


