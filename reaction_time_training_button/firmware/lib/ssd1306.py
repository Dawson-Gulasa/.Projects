# ssd1306.py — ultra-compatible SSD1306 I2C driver (RP2040-safe)
from micropython import const
import framebuf, time

SET_CONTRAST        = const(0x81)
SET_ENTIRE_ON       = const(0xA4)
SET_NORM_INV        = const(0xA6)
SET_DISP            = const(0xAE)
SET_MEM_ADDR        = const(0x20)
SET_COL_ADDR        = const(0x21)
SET_PAGE_ADDR       = const(0x22)
SET_DISP_START_LINE = const(0x40)
SET_SEG_REMAP       = const(0xA0)
SET_MUX_RATIO       = const(0xA8)
SET_COM_OUT_DIR     = const(0xC0)
SET_DISP_OFFSET     = const(0xD3)
SET_COM_PIN_CFG     = const(0xDA)
SET_DISP_CLK_DIV    = const(0xD5)
SET_PRECHARGE       = const(0xD9)
SET_VCOM_DESEL      = const(0xDB)
SET_CHARGE_PUMP     = const(0x8D)

class SSD1306:
    def __init__(self, width, height, external_vcc=False):
        self.width, self.height = width, height
        self.external_vcc = external_vcc
        self.pages = self.height // 8
        self.buffer = bytearray(self.pages * self.width)
        self.framebuf = framebuf.FrameBuffer(self.buffer, self.width, self.height, framebuf.MONO_VLSB)
        self.poweron()
        self.init_display()

    def poweron(self):
        pass

    def write_cmd(self, c): raise NotImplementedError
    def write_data(self, b): raise NotImplementedError

    def init_display(self):
        for c in (
            SET_DISP | 0x00,
            SET_MEM_ADDR, 0x00,                   # Horizontal addressing
            SET_DISP_START_LINE | 0x00,
            SET_SEG_REMAP | 0x01,                 # Mirror X
            SET_MUX_RATIO, self.height - 1,
            SET_COM_OUT_DIR | 0x08,               # Mirror Y
            SET_DISP_OFFSET, 0x00,
            SET_COM_PIN_CFG, 0x12 if self.height == 64 else 0x02,
            SET_DISP_CLK_DIV, 0x80,
            SET_PRECHARGE, 0x22 if self.external_vcc else 0xF1,
            SET_VCOM_DESEL, 0x30,
            SET_CONTRAST, 0x7F,
            SET_ENTIRE_ON,
            SET_NORM_INV,
            SET_CHARGE_PUMP, 0x10 if self.external_vcc else 0x14,
            SET_DISP | 0x01
        ):
            self.write_cmd(c)
        self.fill(0)
        self.show()

    # FrameBuffer helpers
    def fill(self, c): self.framebuf.fill(c)
    def pixel(self, x, y, c): self.framebuf.pixel(x, y, c)
    def text(self, s,x,y,c=1): self.framebuf.text(s,x,y,c)
    def rect(self,x,y,w,h,c): self.framebuf.rect(x,y,w,h,c)
    def fill_rect(self,x,y,w,h,c): self.framebuf.fill_rect(x,y,w,h,c)
    def hline(self,x,y,w,c): self.framebuf.hline(x,y,w,c)
    def vline(self,x,y,h,c): self.framebuf.vline(x,y,h,c)
    def line(self,x1,y1,x2,y2,c): self.framebuf.line(x1,y1,x2,y2,c)
    def scroll(self,dx,dy): self.framebuf.scroll(dx,dy)

    def show(self):
        self.write_cmd(SET_COL_ADDR);  self.write_cmd(0); self.write_cmd(self.width-1)
        self.write_cmd(SET_PAGE_ADDR); self.write_cmd(0); self.write_cmd(self.pages-1)
        # Write in small chunks with tiny gaps to avoid I2C timeouts
        buf = self.buffer
        i = 0
        CH = 16  # chunk size (very safe)
        while i < len(buf):
            self.write_data(buf[i:i+CH])
            i += CH
            time.sleep_us(150)  # tiny breather

class SSD1306_I2C(SSD1306):
    def __init__(self, width, height, i2c, addr=0x3C, external_vcc=False):
        self.i2c = i2c
        self.addr = addr
        super().__init__(width, height, external_vcc)

    def write_cmd(self, c):
        self.i2c.writeto(self.addr, b'\x80' + bytes([c]))

    def write_data(self, b):
        # Control byte 0x40 indicates data stream
        # Send small packets; Pico + some panels dislike big bursts
        self.i2c.writeto(self.addr, b'\x40' + b)
