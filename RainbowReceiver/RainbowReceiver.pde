/**
 * RainbowReceiver
 *
 * Receives ArtNet packets for 2 LED controllers.  Controller 1 is controlling
 * 16 panels.  Controller 2 is controlling 12 panels.  Each panel is 450 pixels.
 * 15 pixels wide by 30 pixels tall.  The LEDS are on a continuous wire of LEDs
 * (like Christmas lights) and chained in lengths of 50.  The wiring diagram
 * for the LEDs starts with 0,0 at the bottom right of a panel.  The wiring
 * then moves vertically until the top of the panel and then moves over to
 * the left one unit and then moves vertically down.  It continues the snaking
 * pattern until ending up at the top left of the panel.  This needs to be
 * accounted for and "unwired" in order to remap our points to an image.  Simple
 * wirings will have much simpler ArtNet to Image decoding.
 */

// import UDP library
import hypermedia.net.*;

int framePacketCount1 = 0;
int framePacketCount2 = 0;

UDP udp1;  // define the UDP object
int udp1Port = 6454;
UDP udp2;
int udp2Port = 6455;
PImage receivedImage1;
PImage receivedImage2;
boolean updateImage1 = false;
boolean updateImage2 = false;
int totalLedsWide = 420;
int totalLedsHigh = 30;
int numControllers = 2;
int numPanelsController1 = 16;
int numPanelsController2 = 12;
int ledsWidePerPanel = 15;
int ledsHighPerPanel = 30;
int ledsWidePanel1 = ledsWidePerPanel * numPanelsController1;
int ledsWidePanel2 = ledsWidePerPanel * numPanelsController2;
long lastSyncPacketTime = System.currentTimeMillis();

/**
 * init
 */
void setup() {
  // Fix this if you change the above.
  size(420, 30);
  receivedImage1 = createImage(ledsWidePanel1, totalLedsHigh, RGB);
  receivedImage1.loadPixels();
  receivedImage2 = createImage(ledsWidePanel2, totalLedsHigh, RGB);
  receivedImage2.loadPixels();
  // create a new datagram connection
  // and wait for incomming message
  udp1 = new UDP(this, udp1Port);
  //udp.log( true ); 		// <-- printout the connection activity
  udp1.setReceiveHandler("receiveLedController1");
  udp1.listen(true);
  
  udp2 = new UDP(this, udp2Port);
  udp2.setReceiveHandler("receiveLedController2");
  udp2.listen(true);
  
}

//process events
void draw() {
  if (updateImage1) {
    image(receivedImage1, 0, 0);
    receivedImage1 = createImage(ledsWidePanel1, totalLedsHigh, RGB);
    receivedImage1.loadPixels();
    updateImage1 = false;
  }
  if (updateImage2) {
    image(receivedImage2, ledsWidePanel1, 0);
    receivedImage2 = createImage(ledsWidePanel2, totalLedsHigh, RGB);
    receivedImage2.loadPixels();
    updateImage2 = false;
  } 
}

void receiveLedController1(byte[] data, String ip, int port) {
  // System.out.println("Controller 1 packet.");
  updateImage1 = receiveCommon(data, ip, port, framePacketCount1, receivedImage1, ledsWidePanel1);
  ++framePacketCount1;
  if (updateImage1) {
    long now = System.currentTimeMillis();
    // System.out.println("pkt ms: " + (now - lastSyncPacketTime));
    framePacketCount1 = 0;
    lastSyncPacketTime = now;
  }
}

void receiveLedController2(byte[] data, String ip, int port) {
  // System.out.println("Controller 2 packet.");
  updateImage2 = receiveCommon(data, ip, port, framePacketCount2, receivedImage2, ledsWidePanel2);
  ++framePacketCount2;
  if (updateImage2)
    framePacketCount2 = 0;
}

boolean receiveCommon( byte[] data, String ip, int port, int framePacketCount, PImage receivedImage, 
  int ledsWideThisController) {
  // println("data.length=" + data.length);

  // Artnet-Sync packets are 14 bytes long.
  if (data.length > 15) {
    // Each packet has a universe number.  Based on the universe #
    // we can compute which region of pixels to update.  Universe #'s
    // are unique with respect to a given controller.
    // Universe it at 14, 15    
    int universeNumber = data[14]&0xff | (data[15]&0xff) << 8;
    // System.out.println("universe #: " + universeNumber);    
    // Data length is 16-17
    int colorsLength = (data[16]&0xff) << 8 | data[17]&0xff;
    // System.out.println("colors length: " + colorsLength);
    int artnetHeaderSize = 18;
    // i 0-170
    int maxColNum = ledsWidePerPanel - 1;
    for (int i = 0; i < colorsLength/3; i++) {
      int red = data[artnetHeaderSize + i*3] & 0xff;
      int green = data[artnetHeaderSize + i*3 + 1] & 0xff;
      int blue = data[artnetHeaderSize + i*3 + 2] & 0xff;
      // System.out.println("red green blue=" + red + " " + green + " " + blue);
      // System.out.println("universeNumber: " + universeNumber);
      // System.out.println("framePacketCount: " + framePacketCount);
      int panelNum = framePacketCount / 3;
      // System.out.println("panelNum: " + panelNum);
      int thisPanelUniverseOffset = universeNumber - panelNum * 3;
      int panelLedPos = thisPanelUniverseOffset * 170 + i;
      int colNumFromRight = panelLedPos / ledsHighPerPanel;
      int colNumFromLeft = maxColNum - colNumFromRight;
      int rowNumFromBottom;
      if (colNumFromRight % 2 == 0)
        rowNumFromBottom = panelLedPos % ledsHighPerPanel;
      else
        rowNumFromBottom = ledsHighPerPanel - panelLedPos % ledsHighPerPanel - 1;
      int pointIndex = rowNumFromBottom * ledsWidePerPanel + colNumFromLeft;
      
      // Now we need to "unwire" our panel
      //System.out.println("panelLedPos: " + panelLedPos);
      //System.out.println("pointIndex: " + pointIndex);
      int panelLedX = pointIndex % ledsWidePerPanel;
      //System.out.println("panelLedX: " + panelLedX);
      int panelLedY = pointIndex / ledsWidePerPanel;
      //System.out.println("panelLedY: " + panelLedY);
      int globalX = panelLedX + panelNum * ledsWidePerPanel;
      int globalY = panelLedY;
      //System.out.println("global x y: " + globalX + " " + globalY);
      // Our LED/Point coordinates in LX Studio are oriented for physical
      // space to simplify physical math patterns.  Need to invert Y for
      // typical image coordinates.
      int globalImgCoord = globalX + (totalLedsHigh - 1 - globalY) * ledsWideThisController;
      //System.out.println("imgCoord= " + globalImgCoord);
      receivedImage.pixels[globalImgCoord] = color(red, green, blue);
    }
  }
  
  // ArtNet sync packet
  if (data[8] == 0x00 && data[9] == 0x52) {
    receivedImage.updatePixels();
    // System.out.println("packet sync, packet count = " + (framePacketCount+1));
    return true;
  }
  return false;
}
