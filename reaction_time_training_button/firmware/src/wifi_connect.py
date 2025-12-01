# wifi_connect.py
import network, time

# Optional status codes (not all ports expose all codes, but useful when present)
STAT_IDLE = getattr(network, "STAT_IDLE", 0)
STAT_CONNECTING = getattr(network, "STAT_CONNECTING", 1)
STAT_WRONG_PASSWORD = getattr(network, "STAT_WRONG_PASSWORD", -3)
STAT_NO_AP_FOUND = getattr(network, "STAT_NO_AP_FOUND", -2)
STAT_GOT_IP = getattr(network, "STAT_GOT_IP", 3)

def connect(ssid, password, timeout_s=30, retries=3, powersave=False):
    wlan = network.WLAN(network.STA_IF)
    wlan.active(True)

    if not powersave:
        try:
            # Disable power-save on CYW43 (can help some APs)
            wlan.config(pm=0xa11140)
        except:
            pass

    for attempt in range(1, retries + 1):
        print(f"[WiFi] Attempt {attempt}/{retries} → {ssid}")
        wlan.disconnect()
        wlan.connect(ssid, password)

        t0 = time.ticks_ms()
        while True:
            if wlan.isconnected():
                print("[WiFi] Connected.")
                return wlan.ifconfig()

            # Print status every ~0.5s
            st = wlan.status() if hasattr(wlan, "status") else None
            if st is not None:
                print(f"  status={st}")

                # Helpful early exits if exposed by port:
                if st == STAT_WRONG_PASSWORD:
                    raise RuntimeError("Wrong Wi-Fi password.")
                if st == STAT_NO_AP_FOUND:
                    break  # try next attempt

            if time.ticks_diff(time.ticks_ms(), t0) > timeout_s * 1000:
                print("[WiFi] Timeout this attempt.")
                break

            time.sleep(0.5)

        time.sleep(1)  # brief pause before retry

    raise RuntimeError("WiFi connection failed (check SSID/pass and network type)")
