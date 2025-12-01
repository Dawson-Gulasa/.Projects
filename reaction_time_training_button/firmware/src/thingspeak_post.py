# thingspeak_post.py
import socket

HOST = "api.thingspeak.com"
PORT = 80

def update(api_key, fields):
    """
    fields: list of numeric/string values for Field1..FieldN
    returns: entry ID (int) or 0 if rate-limited
    """
    # Build query string
    qs = "api_key=" + api_key
    for i, val in enumerate(fields, start=1):
        qs += f"&field{i}={val}"

    addr = socket.getaddrinfo(HOST, PORT)[0][-1]
    s = socket.socket()
    try:
        s.connect(addr)
        req = (f"GET /update?{qs} HTTP/1.1\r\n"
               f"Host: {HOST}\r\n"
               "Connection: close\r\n\r\n")
        s.send(req.encode())
        data = b""
        while True:
            chunk = s.recv(1024)
            if not chunk:
                break
            data += chunk
    finally:
        s.close()

    try:
        body = data.split(b"\r\n\r\n", 1)[1].strip()
        return int(body or b"0")
    except:
        return 0
