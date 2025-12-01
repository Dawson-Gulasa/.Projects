# main.py
# Requires: ssd1306.py, wifi_connect.py, thingspeak_post.py, secrets.py

from machine import Pin, ADC, I2C
import time, math
try:
    import urandom as random
except:
    import random

# ---------------------------
# ---- PIN & HW CONSTANTS ---
# ---------------------------
I2C_ID   = 0
PIN_SCL  = 5
PIN_SDA  = 4
I2C_FREQ = 400000

PIN_LED   = 15
PIN_IR_DO = 16
PIN_FSR_ADC = 26
ADC_VREF  = 3.30

PIN_TH_ADC     = 27
TH_VADC_REF    = 3.30
TH_VIN_BR      = 3.30
TH_VREF_BIAS   = 1.650
TH_INA_GAIN    = 6.00
TH_R_BOTTOM    = 10000.0
TH_R0          = 10000.0
TH_T0_K        = 273.15 + 25.0
TH_BETA        = 3977.0
TH_CAL_OFFSET_C = 0.0
THERMISTOR_CALIBRATION = 0

TEMP_LIMIT_F = 95.0

CHEAT_MSG_MS     = 1200
REACTION_WIN_MS  = 1500
LED_DELAY_MIN_MS = 3000
LED_DELAY_MAX_MS = 8000

FSR_NSAMP = 8
FSR_DT_US = 150
FSR_KF_Q  = 5e-5
FSR_KF_R  = 2e-4
FSR_PRESS_N = 1.0

LEADERBOARD_SHOW_MS = 5000
USE_THINGSPEAK = True

# ---------------------------
# ---- WiFi / ThingSpeak ----
# ---------------------------
import network
from wifi_connect import connect as wifi_connect
from thingspeak_post import update as ts_update
from secrets import WIFI_SSID, WIFI_PASS, TS_WRITE_KEY, TS_READ_KEY, TS_CHANNEL_ID

TS_HOST = "api.thingspeak.com"
TS_PORT = 80
TS_RESULTS_FETCH = 100
TS_MIN_REFRESH_MS = 15000

_last_ts_pull = -10_000_000
_cached_top3  = []

wlan = network.WLAN(network.STA_IF)
wlan.active(True)

def ensure_wifi_connected(timeout_s=20):
    if wlan.isconnected():
        return True
    oled_msg(["Connecting WiFi..."], box=True)
    wlan.connect(WIFI_SSID, WIFI_PASS)
    t0 = time.ticks_ms()
    while not wlan.isconnected() and time.ticks_diff(time.ticks_ms(), t0) < timeout_s*1000:
        time.sleep_ms(200)
    return wlan.isconnected()

def ts_post_reaction_ms(rm):
    if not (USE_THINGSPEAK and ensure_wifi_connected(20)):
        return False
    try:
        return ts_update(TS_WRITE_KEY, [int(rm)]) > 0
    except:
        return False

def ts_fetch_top3_ms():
    global _last_ts_pull, _cached_top3
    if not USE_THINGSPEAK:
        return []
    if (time.ticks_diff(now_ms(), _last_ts_pull) < TS_MIN_REFRESH_MS) and _cached_top3:
        return _cached_top3
    if not ensure_wifi_connected(20):
        return _cached_top3

    import socket
    try:
        path = "/channels/{}/fields/1.json?api_key={}&results={}".format(
            TS_CHANNEL_ID, TS_READ_KEY, TS_RESULTS_FETCH)

        addr = socket.getaddrinfo(TS_HOST, TS_PORT)[0][-1]
        s = socket.socket()
        s.connect(addr)
        s.send(("GET {} HTTP/1.1\r\nHost: {}\r\nConnection: close\r\n\r\n"
                .format(path, TS_HOST)).encode())

        data = b""
        while True:
            chunk = s.recv(1024)
            if not chunk:
                break
            data += chunk
        s.close()

        body = data.split(b"\r\n\r\n", 1)[1]

        import ujson as json
        feeds = json.loads(body).get("feeds", [])
        vals = []
        for f in feeds:
            v = f.get("field1")
            if v:
                try:
                    vals.append(float(v))
                except:
                    pass

        vals.sort()
        _cached_top3 = [int(x) for x in vals[:3]]
        _last_ts_pull = now_ms()
        return _cached_top3

    except:
        return _cached_top3

# ---------------------------
# ---- OLED SETUP -----------
# ---------------------------
from ssd1306 import SSD1306_I2C
i2c = I2C(I2C_ID, scl=Pin(PIN_SCL), sda=Pin(PIN_SDA), freq=I2C_FREQ)
addr_list = i2c.scan()
oled_addr = 0x3C if 0x3C in addr_list else (0x3D if 0x3D in addr_list else 0x3C)
oled = SSD1306_I2C(128, 64, i2c, addr=oled_addr, external_vcc=False)

def oled_msg(lines, box=False):
    oled.fill(0)
    if box: oled.rect(0,0,128,64,1)
    y = 4
    for s in lines[:6]:
        oled.text(s, 4, y)
        y += 10
    oled.show()

def oled_result(rt_ms, max_force_n):
    oled.fill(0)
    oled.rect(0,0,128,64,1)
    oled.text("Results", 36, 4)
    oled.hline(4, 16, 120, 1)
    oled.text("Time:", 4, 28)
    oled.text("{:4d} ms".format(int(rt_ms)), 64, 28)
    oled.text("Force:", 4, 44)
    oled.text("{:.2f} N".format(max_force_n), 64, 44)
    oled.show()

def oled_top3_ms(top3_ms):
    oled.fill(0)
    oled.rect(0,0,128,64,1)
    oled.text("Top 3 (ms)", 26, 4)
    oled.hline(4, 16, 120, 1)
    y = 26
    if not top3_ms:
        oled.text("No data yet.", 20, 36)
    else:
        for rank, ms in enumerate(top3_ms[:3], start=1):
            oled.text("{}:{:>5d}".format(rank, int(ms)), 28, y)
            y += 12
    oled.show()

# ===============================================================
#  SENSOR SUBFUNCTIONS — CLEANLY GROUPED (FSR, IR, THERMISTOR)
# ===============================================================

# ---------------------------
# ---- IR SENSOR ------------
# ---------------------------
ir_do = Pin(PIN_IR_DO, Pin.IN, Pin.PULL_UP)

def ir_read_raw():
    return (ir_do.value() == 0)

def ir_read_filtered(samples=5, gap_ms=2):
    hits = 0
    for _ in range(samples):
        if ir_read_raw():
            hits += 1
        time.sleep_ms(gap_ms)
    return (hits >= (samples // 2 + 1))


# ---------------------------
# ---- FSR ------------------
# ---------------------------
fsr_adc = ADC(PIN_FSR_ADC)

def fsr_read_voltage():
    s = 0
    for _ in range(FSR_NSAMP):
        s += fsr_adc.read_u16()
        time.sleep_us(FSR_DT_US)
    raw = s // FSR_NSAMP
    return (raw / 65535.0) * ADC_VREF, raw

class Kalman1D:
    def __init__(self, q=FSR_KF_Q, r=FSR_KF_R, x0=0.0, p0=1.0):
        self.x = x0
        self.P = p0
        self.Q = q
        self.R = r
    def update(self, z):
        xp = self.x
        Pp = self.P + self.Q
        K = Pp / (Pp + self.R)
        self.x = xp + K * (z - xp)
        self.P = (1.0 - K) * Pp
        return self.x

fsr_kf = Kalman1D()

PTS = [
    (0.00, 0.000),
    (1.25, 1.049),
    (1.90, 2.030),
    (2.40, 3.012),
    (2.50, 3.990),
    (2.75, 4.972),
    (2.85, 5.953),
    (2.90, 6.930)
]
V_SAT = 2.90
F_AT_VSAT = 6.930

def fsr_force_from_v(v):
    if v <= PTS[0][0]:
        return PTS[0][1]
    if v >= V_SAT:
        return F_AT_VSAT
    for (vx0, fx0), (vx1, fx1) in zip(PTS, PTS[1:]):
        if vx0 <= v <= vx1:
            return fx0 + (fx1 - fx0) * (v - vx0) / (vx1 - vx0)
    return F_AT_VSAT

def fsr_read_force():
    v, _ = fsr_read_voltage()
    v_f = fsr_kf.update(v)
    return fsr_force_from_v(v_f), v_f


# ---------------------------
# ---- THERMISTOR ----------
# ---------------------------
th_adc = ADC(PIN_TH_ADC)

_TH_AVG_N = 8
_th_buf = [0] * _TH_AVG_N
_th_sum = 0
_th_i = 0
_th_filled = 0

def th_read_counts_12b():
    return th_adc.read_u16() >> 4

def th_read_smooth_counts():
    global _th_sum, _th_i, _th_filled
    c = th_read_counts_12b()
    old = _th_buf[_th_i]
    _th_buf[_th_i] = c
    _th_i = (_th_i + 1) % _TH_AVG_N
    if _th_filled < _TH_AVG_N:
        _th_sum += c
        _th_filled += 1
        return _th_sum // _th_filled
    else:
        _th_sum += c - old
        return _th_sum // _TH_AVG_N

def th_counts_to_vout(c):
    return (c / 4095.0) * TH_VADC_REF

def th_vout_to_v1(vout):
    return TH_VREF_BIAS - (vout - TH_VREF_BIAS) / TH_INA_GAIN

def th_v1_to_rt(v1):
    eps = 1e-6
    v1c = min(TH_VIN_BR - eps, max(eps, v1))
    return TH_R_BOTTOM * (TH_VIN_BR / v1c - 1.0)

def th_rt_to_c(rt):
    try:
        invT = (1.0 / TH_T0_K) + (1.0 / TH_BETA) * math.log(rt / TH_R0)
        T_K = 1.0 / invT
        return (T_K - 273.15) + TH_CAL_OFFSET_C
    except:
        return float('nan')

def th_read_temp_c_f():
    c = th_read_smooth_counts()
    vout = th_counts_to_vout(c)
    v1 = th_vout_to_v1(vout)
    rt = th_v1_to_rt(v1)
    t_c = th_rt_to_c(rt)
    t_f = (t_c * 9.0 / 5.0 + 32.0 + THERMISTOR_CALIBRATION) if (t_c == t_c) else t_c
    return t_c, t_f

# ===============================================================
# ========== EVERYTHING BELOW THIS LINE IS UNCHANGED ============
# ===============================================================

def now_ms(): return time.ticks_ms()
def ms_since(t0): return time.ticks_diff(now_ms(), t0)

def rand_delay_ms():
    span = (LED_DELAY_MAX_MS - LED_DELAY_MIN_MS + 1)
    try: 
        r = random.getrandbits(16) % span
    except:
        r = int((time.ticks_us() & 0xFFFF) % span)
    return LED_DELAY_MIN_MS + r

# ---------------------------
# ---- STATE MACHINE --------
# ---------------------------
STATE_WAIT_ARM=0; STATE_WAIT_RELEASE=1; STATE_PRIMED=2; STATE_ANTICHEAT=3
STATE_LED_ON=4; STATE_SHOW_RESULT=5; STATE_ERROR=6; STATE_SHOW_TOP3=7

state=STATE_WAIT_ARM
pending_reaction=None; pending_peak=None
led.off()
oled_msg(["Press button to","start!"],box=True)

t_delay_target=None; t_led_on=None; t_fsr_hit=None; t_ir_hit=None
upload_done=False; upload_time=None

while True:

    t_c,t_f = th_read_temp_c_f()

    if (t_f==t_f) and (t_f > TEMP_LIMIT_F):
        state=STATE_ERROR

    if state==STATE_ERROR:
        led.off()
        oled_msg(
            ["Error - Too hot","Temp: {:.1f} F".format(t_f),"Power down & cool"],
            box=True
        )
        while True:
            time.sleep_ms(200)

    force_n, fsr_v = fsr_read_force()
    fsr_pressed = (force_n >= FSR_PRESS_N)
    ir_present  = ir_read_filtered(5,2)

    if state==STATE_WAIT_ARM:
        led.off()
        oled_msg(["Press button to","    start!"," ","Temp: {:.1f}F".format(t_f)])
        if fsr_pressed and ir_present:
            state=STATE_WAIT_RELEASE
            time.sleep_ms(50)

    elif state==STATE_WAIT_RELEASE:
        oled_msg([" ","  Release to","    begin"])
        if (not fsr_pressed) and (not ir_present):
            state=STATE_PRIMED
            t_delay_target=None

    elif state==STATE_PRIMED:
        led.off()
        if t_delay_target is None:
            oled_msg(["  Game Started","  Wait for LED","  No touching!"])
            t_delay_target = now_ms() + rand_delay_ms()
            t_fsr_hit=None
            t_ir_hit=None
        if fsr_pressed or ir_present:
            state=STATE_ANTICHEAT
            t_cheat = now_ms()
            oled_msg(["  Don't Cheat!","  Wait for LED"],box=True)
        elif time.ticks_diff(t_delay_target, now_ms()) <= 0:
            led.on()
            t_led_on = now_ms()
            state=STATE_LED_ON
            oled_msg(["    LED ON!","   Press the","    button!"],box=True)

    elif state==STATE_ANTICHEAT:
        if ms_since(t_cheat) >= CHEAT_MSG_MS:
            state=STATE_PRIMED
            t_delay_target=None

    elif state==STATE_LED_ON:
        if (t_fsr_hit is None) and fsr_pressed:
            t_fsr_hit = now_ms()
        if (t_ir_hit is None) and ir_present:
            t_ir_hit  = now_ms()

        if (t_fsr_hit is not None) and (t_ir_hit is not None):
            rt_fsr = time.ticks_diff(t_fsr_hit, t_led_on)
            rt_ir  = time.ticks_diff(t_ir_hit,  t_led_on)
            reaction_ms = (rt_fsr + rt_ir) / 2.0

            peak_n = force_n
            t_cap0 = now_ms()
            while ms_since(t_cap0) < REACTION_WIN_MS:
                f_n,_ = fsr_read_force()
                if f_n > peak_n:
                    peak_n = f_n
                t_c2,t_f2 = th_read_temp_c_f()
                if (t_f2==t_f2) and (t_f2 > TEMP_LIMIT_F):
                    state=STATE_ERROR
                    break
                time.sleep_ms(10)

            led.off()

            if state != STATE_ERROR:
                pending_reaction = reaction_ms
                pending_peak = peak_n
                oled_result(reaction_ms, peak_n)
                show_t0 = now_ms()
                upload_done=False
                upload_time=None
                state=STATE_SHOW_RESULT

    elif state==STATE_SHOW_RESULT:

        if (not upload_done) and (ms_since(show_t0) > 1000):
            upload_done = ts_post_reaction_ms(pending_reaction)
            upload_time = now_ms()

        if upload_done and (ms_since(upload_time) > 20000):
            top3 = ts_fetch_top3_ms()
            oled_top3_ms(top3)
            top3_t0 = now_ms()
            state = STATE_SHOW_TOP3

    elif state==STATE_SHOW_TOP3:
        if ms_since(top3_t0) >= LEADERBOARD_SHOW_MS:
            state = STATE_WAIT_ARM
            oled_msg(["Press button to","start!","Ready..."],box=True)
            led.off()

    time.sleep_ms(20)

