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

boolean twoInputsPerPanel = true;
int ledsPerInput1 = 250;
int ledsPerInput2 = 200;
int expandedModeUniversesPerPanel = 4;

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
  if (!twoInputsPerPanel)
    udp1.setReceiveHandler("receiveLedController1");
  else
    udp1.setReceiveHandler("twoInputsReceiveLedController1");
  udp1.listen(true);
  
  udp2 = new UDP(this, udp2Port);
  if (!twoInputsPerPanel)
    udp2.setReceiveHandler("receiveLedController2");
  else
    udp2.setReceiveHandler("twoInputsReceiveLedController2");
  udp2.listen(true);
  background(127);
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
      int wireLedPos = thisPanelUniverseOffset * 170 + i;
      int currentLogicalPanel = panelNum;
      int colNumFromRight = -1;
      int colNumFromLeft = -1;
      int rowNumFromBottom = -1;
      int maxColNumPerPanel = ledsWidePerPanel - 1;
      int pointsHighPerPanel = ledsHighPerPanel;
      boolean startPanel = false;
      boolean endPanel = false;
      int numPanels = 1; // For start/end panel testing.
      
        // NOTE(tracy):  This code is duplicated in patterns.PanelWire which implements a pattern
        // that traces out the wiring.  Even better, the start panel and end panel wiring cases
        // below are very similar but mirrored about X.
        // Handle start panel, panel variant E special case.
        if (startPanel && currentLogicalPanel == 0) {
          // First 300 leds (6 strands are wired normal but mirrored in X dimension, start at bottom right on front
          if (wireLedPos < 300) {
            colNumFromRight = wireLedPos / pointsHighPerPanel;
            colNumFromLeft = maxColNumPerPanel - colNumFromRight;
            if (colNumFromRight % 2 == 0)
              rowNumFromBottom = wireLedPos % pointsHighPerPanel;
            else
              rowNumFromBottom = pointsHighPerPanel - wireLedPos % pointsHighPerPanel - 1;
          } else {
            // String #7 starts on normal column, row 4, goes up and back down.  Last 2 leds are on the wire
            // but not used.  Unused leds on a wire require skipping a couple dmx channels.  Normally, that would
            // be bad because we are packing the max pixels per universe, so 2 extra pixels pushes the typical
            // universe boundaries to different locations but overall these panels have less pixels so each
            // panel will still use 3 universes.
            if (wireLedPos >= 300 && wireLedPos < 350) {
              // String #7 wiring
              int string7WirePos = wireLedPos - 300;
              int string7StartRow = 3;  // Mingjing said Row 4, 1-based.
              if (string7WirePos <= 26) {
                colNumFromLeft = 4;
                rowNumFromBottom = string7WirePos + 3;
              } else if (string7WirePos <= 47) {
                colNumFromLeft = 3;
                rowNumFromBottom = pointsHighPerPanel - (string7WirePos - 26);
              } else {  // Leds 49,50 or 0-based position 48,49 are unused LEDS
                colNumFromLeft = -1;
              }
            } else if (wireLedPos >= 350) {
              // String #8 wiring
              int string8WirePos = wireLedPos - 350;
              int string8StartRow = 14;
              int string8StartRow2 = 20;
              int string8StartRow3 = 26;
              // Start on row 15 (14 in 0 base), install 26 Leds. First column is from
              // 29-14 = 15 which is 16 leds from 14-29 inclusive 0-based.  That leaves 10 leds for
              // the next column which is 29-20 inclusive 0-based or 30-21 in 1-based.
              // This segment also includes 4 dead leds serving as a wire extension for a total of 34 leds.
              // That is 16 leds short of a typical 50-led wire.
              if (string8WirePos <= 15) {
                colNumFromLeft = 2;
                rowNumFromBottom = string8StartRow + string8WirePos;
              } else if (string8WirePos >= 16 && string8WirePos < 26) {
                colNumFromLeft = 1;
                rowNumFromBottom = (pointsHighPerPanel-1) - (string8WirePos - 16);
              } else if (string8WirePos >= 26 && string8WirePos < 30) {
                colNumFromLeft = -1; // Sentinel to mark unused leds in the wires.
              } else if (string8WirePos >= 30 && string8WirePos < 34) {
                colNumFromLeft = 0;
                rowNumFromBottom = string8WirePos - 30 + string8StartRow3;
              } else {  // At the end of the wiring.  Just make these dead leds that are skipped.
                colNumFromLeft = -1;
              }
            }
          }
          //System.out.println("colFromLeft: " + colNumFromLeft + " colFromRight:" + colNumFromRight);
        } else if (endPanel && currentLogicalPanel <= numPanels - 1) {
          // Handle end panel, panel variant H special case.
          // The first 300 leds are the typical wiring.
          if (wireLedPos < 300) {
            colNumFromLeft = wireLedPos / pointsHighPerPanel;
            colNumFromRight = maxColNumPerPanel - colNumFromLeft;
            if (colNumFromLeft % 2 == 0)
              rowNumFromBottom = wireLedPos % pointsHighPerPanel;
            else
              rowNumFromBottom = pointsHighPerPanel - wireLedPos % pointsHighPerPanel - 1;
          } else {
            // String #7 starts on normal column, row 4, goes up and back down.  Last 2 leds are on the wire
            // but not used.  Unused leds on a wire require skipping a couple dmx channels.  Normally, that would
            // be bad because we are packing the max pixels per universe, so 2 extra pixels pushes the typical
            // universe boundaries to different locations but overall these panels have less pixels so each
            // panel will still use 3 universes.
            if (wireLedPos >= 300 && wireLedPos < 350) {
              //String #7 wiring
              int string7WirePos = wireLedPos - 300;
              int string7StartRow = 3;  // Mingjing said Row 4, 1-based.
              if (string7WirePos <= 26) {
                colNumFromLeft = 10;
                rowNumFromBottom = string7WirePos + 3;
              } else if (string7WirePos <= 47) {
                colNumFromLeft = 11;
                rowNumFromBottom = pointsHighPerPanel - (string7WirePos - 26);
              } else {  // Leds 49,50 or 0-based position 48,49 are unused LEDS
                colNumFromLeft = -1;
              }
            } else if (wireLedPos >= 350) {
              // String #8 wiring
              int string8WirePos = wireLedPos - 350;
              int string8StartRow = 14;
              int string8StartRow2 = 20;
              int string8StartRow3 = 26;
              // Start on row 15 (14 in 0 base), install 26 Leds. First column is from
              // 29-14 = 15 which is 16 leds from 14-29 inclusive 0-based.  That leaves 10 leds for
              // the next column which is 29-20 inclusive 0-based or 30-21 1-based.
              // This segment also includes 4 dead leds serving as a wire extension for a
              // total of 34 leds.  That is 16 short of a normal strand.
              if (string8WirePos <= 15) {
                colNumFromLeft = 12;
                rowNumFromBottom = string8StartRow + string8WirePos;
              } else if (string8WirePos >= 16 && string8WirePos < 26) {
                colNumFromLeft = 13;
                rowNumFromBottom = (pointsHighPerPanel-1) - (string8WirePos - 16);
              } else if (string8WirePos >= 26 && string8WirePos < 30) {
                colNumFromLeft = -1; // Sentinel to mark unused leds in the wires.
              } else if (string8WirePos >= 30 && string8WirePos < 34) {
                colNumFromLeft = 14;
                rowNumFromBottom = string8WirePos - 30 + string8StartRow3;
              } else {  // At the end of the wiring.  Just make these dead leds that are skipped.
                colNumFromLeft = -1;
              }
            }
          }
          // logger.info("colFromLeft: " + colNumFromLeft + " colFromRight:" + colNumFromRight);
        } else {
          // Standard Panels
          colNumFromLeft = wireLedPos / pointsHighPerPanel;
          colNumFromRight = maxColNumPerPanel - colNumFromLeft;
          //logger.info("colFromLeft: " + colNumFromLeft + " colFromRight:" + colNumFromRight);

          if (colNumFromRight % 2 == 0)
            rowNumFromBottom = wireLedPos % pointsHighPerPanel;
          else
            rowNumFromBottom = pointsHighPerPanel - wireLedPos % pointsHighPerPanel - 1;
        }
      //if (colNumFromLeft == -1)
      //  continue;
        
      int pointIndex = rowNumFromBottom * ledsWidePerPanel + colNumFromLeft;
      
      // Now we need to "unwire" our panel
      int panelLedX = pointIndex % ledsWidePerPanel;
      //
      int panelLedY = pointIndex / ledsWidePerPanel;
      //
      int globalX = panelLedX + panelNum * ledsWidePerPanel;
      int globalY = panelLedY;
      //
      // Our LED/Point coordinates in LX Studio are oriented for physical
      // space to simplify physical math patterns.  Need to invert Y for
      // typical image coordinates.
      int globalImgCoord = globalX + (totalLedsHigh - 1 - globalY) * ledsWideThisController;
      if (wireLedPos == 0) {
        System.out.println("-------------------- 0 wire ------------------");
        System.out.println("wireLedPos: " + wireLedPos);
        System.out.println("pointIndex: " + pointIndex);
        System.out.println("panelLedX: " + panelLedX);
        System.out.println("panelLedY: " + panelLedY);
        System.out.println("global x y: " + globalX + " " + globalY);
        System.out.println("imgCoord= " + globalImgCoord);
        System.out.println("rgb: " + red + " " + green + " " + blue);
      } else if (globalImgCoord == 449) {
        System.out.println("ugh wireLedPos: " + wireLedPos);
      }


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

void twoInputsReceiveLedController1(byte[] data, String ip, int port) {
  updateImage1 = twoInputsReceiveCommon(data, ip, port, framePacketCount1, receivedImage1, ledsWidePanel1);
  ++framePacketCount1;
  if (updateImage1) {
    long now = System.currentTimeMillis();
    // System.out.println("pkt ms: " + (now - lastSyncPacketTime));
    framePacketCount1 = 0;
    lastSyncPacketTime = now;
  }
}

void twoInputsReceiveLedController2(byte[] data, String ip, int port) {
  updateImage2 = twoInputsReceiveCommon(data, ip, port, framePacketCount2, receivedImage2, ledsWidePanel2);
  ++framePacketCount2;
  if (updateImage2)
    framePacketCount2 = 0;
}

/**
 * Process ArtNet Data for panels with 2 inputs per panel.  Each input should be either 250
 * or 200 pixels.  This configuration is for running WS2811 leds on a Pixlite in expanded
 * mode so that we can increase our FPS.
 */
boolean twoInputsReceiveCommon( byte[] data, String ip, int port, int framePacketCount, PImage receivedImage, 
  int ledsWideThisController) {
  // println("data.length=" + data.length);

  // Artnet-Sync packets are 14 bytes long.
  if (data.length > 15) {
    // Each packet has a universe number.  Based on the universe #
    // we can compute which region of pixels to update.  Universe #'s
    // are unique with respect to a given controller.
    // Universe is at byte offset 14, 15    
    int universeNumber = data[14]&0xff | (data[15]&0xff) << 8;
    // System.out.println("universe #: " + universeNumber);    
    // Data length is at byte offets 16-17
    int colorsLength = (data[16]&0xff) << 8 | data[17]&0xff;
    // System.out.println("colors length: " + colorsLength);
    int artnetHeaderSize = 18;
    // i 0-170
    int maxColNum = ledsWidePerPanel - 1;
    // System.out.println("points=" + colorsLength/3);
    for (int i = 0; i < colorsLength/3; i++) {
      int red = data[artnetHeaderSize + i*3] & 0xff;
      int green = data[artnetHeaderSize + i*3 + 1] & 0xff;
      int blue = data[artnetHeaderSize + i*3 + 2] & 0xff;
      //System.out.println("red green blue=" + red + " " + green + " " + blue);
      //System.out.println("universeNumber: " + universeNumber);
      //System.out.println("framePacketCount: " + framePacketCount);
      // Here we map the framePacketCount into a panel number.  
      // TODO(tracy): This needs to be fixed since we are not guaranteed in-order
      // delivery.  We should compute the panelNum based on our parsed universe
      // number and the expected number of universes per panel.  For expanded mode
      // we expect 2 universes per panel input for a total of four universes per
      // panel.
      int panelNum = universeNumber / expandedModeUniversesPerPanel;
      //System.out.println("panelNum: " + panelNum);
      
      // The universe offset relative to this panel, should be 0-3.
      int thisPanelUniverseOffset = universeNumber % expandedModeUniversesPerPanel;
      // The universe offset relative to a panel input, should be 0-1.
      int thisInputUniverseOffset = thisPanelUniverseOffset % 2;
      // TODO(tracy):  The wireLedPos becomes trickier because we don't have a simple run
      // of 170-sized blocks of pixels.  For the 250 pixel scenario, we have 170 + 80.  For the
      // 200 pixel scenario, we have 170 + 30.  Or universe 1 = +170, universe 2 = +80, universe
      // 3 = +170.
      int wireLedPos = i;

      if (thisPanelUniverseOffset == 1)
        wireLedPos = 170 + i;
      else if (thisPanelUniverseOffset == 2)
        wireLedPos = 250 + i;
      else if (thisPanelUniverseOffset == 3)
        wireLedPos = 250 + 170 + i;
      
      int currentLogicalPanel = panelNum;
      int colNumFromRight = -1;
      int colNumFromLeft = -1;
      int rowNumFromBottom = -1;
      int maxColNumPerPanel = ledsWidePerPanel - 1;
      int pointsHighPerPanel = ledsHighPerPanel;
      boolean startPanel = false;
      boolean endPanel = false;
      int numPanels = 1; // For start/end panel testing.
      
        // NOTE(tracy):  This code is duplicated in patterns.PanelWire which implements a pattern
        // that traces out the wiring.  Even better, the start panel and end panel wiring cases
        // below are very similar but mirrored about X.
        // Handle start panel, panel variant E special case.
        if (startPanel && currentLogicalPanel == 0) {
          // First 300 leds (6 strands are wired normal but mirrored in X dimension, start at bottom right on front
          if (wireLedPos < 300) {
            colNumFromRight = wireLedPos / pointsHighPerPanel;
            colNumFromLeft = maxColNumPerPanel - colNumFromRight;
            if (colNumFromRight % 2 == 0)
              rowNumFromBottom = wireLedPos % pointsHighPerPanel;
            else
              rowNumFromBottom = pointsHighPerPanel - wireLedPos % pointsHighPerPanel - 1;
          } else {
            // String #7 starts on normal column, row 4, goes up and back down.  Last 2 leds are on the wire
            // but not used.  Unused leds on a wire require skipping a couple dmx channels.  Normally, that would
            // be bad because we are packing the max pixels per universe, so 2 extra pixels pushes the typical
            // universe boundaries to different locations but overall these panels have less pixels so each
            // panel will still use 3 universes.
            if (wireLedPos >= 300 && wireLedPos < 350) {
              // String #7 wiring
              int string7WirePos = wireLedPos - 300;
              int string7StartRow = 3;  // Mingjing said Row 4, 1-based.
              if (string7WirePos <= 26) {
                colNumFromLeft = 4;
                rowNumFromBottom = string7WirePos + 3;
              } else if (string7WirePos <= 47) {
                colNumFromLeft = 3;
                rowNumFromBottom = pointsHighPerPanel - (string7WirePos - 26);
              } else {  // Leds 49,50 or 0-based position 48,49 are unused LEDS
                colNumFromLeft = -1;
              }
            } else if (wireLedPos >= 350) {
              // String #8 wiring
              int string8WirePos = wireLedPos - 350;
              int string8StartRow = 14;
              int string8StartRow2 = 20;
              int string8StartRow3 = 26;
              // Start on row 15 (14 in 0 base), install 26 Leds. First column is from
              // 29-14 = 15 which is 16 leds from 14-29 inclusive 0-based.  That leaves 10 leds for
              // the next column which is 29-20 inclusive 0-based or 30-21 in 1-based.
              // This segment also includes 4 dead leds serving as a wire extension for a total of 34 leds.
              // That is 16 leds short of a typical 50-led wire.
              if (string8WirePos <= 15) {
                colNumFromLeft = 2;
                rowNumFromBottom = string8StartRow + string8WirePos;
              } else if (string8WirePos >= 16 && string8WirePos < 26) {
                colNumFromLeft = 1;
                rowNumFromBottom = (pointsHighPerPanel-1) - (string8WirePos - 16);
              } else if (string8WirePos >= 26 && string8WirePos < 30) {
                colNumFromLeft = -1; // Sentinel to mark unused leds in the wires.
              } else if (string8WirePos >= 30 && string8WirePos < 34) {
                colNumFromLeft = 0;
                rowNumFromBottom = string8WirePos - 30 + string8StartRow3;
              } else {  // At the end of the wiring.  Just make these dead leds that are skipped.
                colNumFromLeft = -1;
              }
            }
          }
          System.out.println("colFromLeft: " + colNumFromLeft + " colFromRight:" + colNumFromRight);
        } else if (endPanel && currentLogicalPanel == (numPanels - 1)) {
          // Handle end panel, panel variant H special case.
          // The first 300 leds are the typical wiring.
          if (wireLedPos < 300) {
            colNumFromLeft = wireLedPos / pointsHighPerPanel;
            colNumFromRight = maxColNumPerPanel - colNumFromLeft;
            if (colNumFromLeft % 2 == 0)
              rowNumFromBottom = wireLedPos % pointsHighPerPanel;
            else
              rowNumFromBottom = pointsHighPerPanel - wireLedPos % pointsHighPerPanel - 1;
          } else {
            // String #7 starts on normal column, row 4, goes up and back down.  Last 2 leds are on the wire
            // but not used.  Unused leds on a wire require skipping a couple dmx channels.  Normally, that would
            // be bad because we are packing the max pixels per universe, so 2 extra pixels pushes the typical
            // universe boundaries to different locations but overall these panels have less pixels so each
            // panel will still use 3 universes.
            if (wireLedPos >= 300 && wireLedPos < 350) {
              //String #7 wiring
              int string7WirePos = wireLedPos - 300;
              int string7StartRow = 3;  // Mingjing said Row 4, 1-based.
              if (string7WirePos <= 26) {
                colNumFromLeft = 10;
                rowNumFromBottom = string7WirePos + 3;
              } else if (string7WirePos <= 47) {
                colNumFromLeft = 11;
                rowNumFromBottom = pointsHighPerPanel - (string7WirePos - 26);
              } else {  // Leds 49,50 or 0-based position 48,49 are unused LEDS
                colNumFromLeft = -1;
              }
            } else if (wireLedPos >= 350) {
              // String #8 wiring
              int string8WirePos = wireLedPos - 350;
              int string8StartRow = 14;
              int string8StartRow2 = 20;
              int string8StartRow3 = 26;
              // Start on row 15 (14 in 0 base), install 26 Leds. First column is from
              // 29-14 = 15 which is 16 leds from 14-29 inclusive 0-based.  That leaves 10 leds for
              // the next column which is 29-20 inclusive 0-based or 30-21 1-based.
              // This segment also includes 4 dead leds serving as a wire extension for a
              // total of 34 leds.  That is 16 short of a normal strand.
              if (string8WirePos <= 15) {
                colNumFromLeft = 12;
                rowNumFromBottom = string8StartRow + string8WirePos;
              } else if (string8WirePos >= 16 && string8WirePos < 26) {
                colNumFromLeft = 13;
                rowNumFromBottom = (pointsHighPerPanel-1) - (string8WirePos - 16);
              } else if (string8WirePos >= 26 && string8WirePos < 30) {
                colNumFromLeft = -1; // Sentinel to mark unused leds in the wires.
              } else if (string8WirePos >= 30 && string8WirePos < 34) {
                colNumFromLeft = 14;
                rowNumFromBottom = string8WirePos - 30 + string8StartRow3;
              } else {  // At the end of the wiring.  Just make these dead leds that are skipped.
                colNumFromLeft = -1;
              }
            }
          }
          // logger.info("colFromLeft: " + colNumFromLeft + " colFromRight:" + colNumFromRight);
        } else {
          // Standard Panels
          colNumFromLeft = wireLedPos / pointsHighPerPanel;
          colNumFromRight = maxColNumPerPanel - colNumFromLeft;
          //logger.info("colFromLeft: " + colNumFromLeft + " colFromRight:" + colNumFromRight);

          if (colNumFromRight % 2 == 0)
            rowNumFromBottom = wireLedPos % pointsHighPerPanel;
          else
            rowNumFromBottom = pointsHighPerPanel - wireLedPos % pointsHighPerPanel - 1;
        }
      //if (colNumFromLeft == -1)
      //  continue;
        
      int pointIndex = rowNumFromBottom * ledsWidePerPanel + colNumFromLeft;
      
      // Now we need to "unwire" our panel
      int panelLedX = pointIndex % ledsWidePerPanel;
      //
      int panelLedY = pointIndex / ledsWidePerPanel;
      //
      int globalX = panelLedX + panelNum * ledsWidePerPanel;
      int globalY = panelLedY;
      //
      // Our LED/Point coordinates in LX Studio are oriented for physical
      // space to simplify physical math patterns.  Need to invert Y for
      // typical image coordinates.
      int globalImgCoord = globalX + (totalLedsHigh - 1 - globalY) * ledsWideThisController;
      // Change this to 449 to dump some logging at the end of each panel.
      if (wireLedPos == 450) {
        System.out.println("-------------------- 0 wire ------------------");
        System.out.println("wireLedPos: " + wireLedPos);
        System.out.println("pointIndex: " + pointIndex);
        System.out.println("panelLedX: " + panelLedX);
        System.out.println("panelLedY: " + panelLedY);
        System.out.println("global x y: " + globalX + " " + globalY);
        System.out.println("imgCoord= " + globalImgCoord);
        System.out.println("rgb: " + red + " " + green + " " + blue);
      } else if (globalImgCoord == 449) {
        //System.out.println("ugh wireLedPos: " + wireLedPos);
      }
      
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
