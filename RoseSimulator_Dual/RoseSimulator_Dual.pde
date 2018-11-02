/*

  Rose Simulator and Lighter
  
  1. Simulator: draws rose shape on the monitor
  2. Lighter: sends data to the lights
  
  DUAL SHOWS - Works!
  
  HSV colors (not RGB) for better interpolation
  
  11/2/18
  
  x,y coordinates are p,d (petal, distance) coordinates.
  petal = axial, distance = radial. petal is 0-23, distance is 0-5.
  Turn on the coordinates to see the system.
    
*/

byte NUM_BIG_ROSE = 3;  // Number of Big Roses

import com.heroicrobot.dropbit.registry.*;
import com.heroicrobot.dropbit.devices.pixelpusher.Pixel;
import com.heroicrobot.dropbit.devices.pixelpusher.Strip;
import com.heroicrobot.dropbit.devices.pixelpusher.PixelPusher;
import com.heroicrobot.dropbit.devices.pixelpusher.PusherCommand;

import processing.net.*;
import java.util.*;
import java.util.regex.*;
import java.awt.Color;

int NUM_CHANNELS = 2;  // Dual shows

// network vars
int port = 4444;
Server[] _servers = new Server[NUM_CHANNELS];  // For dual shows 
StringBuffer[] _bufs = new StringBuffer[NUM_CHANNELS];  // separate buffers

class TestObserver implements Observer {
  public boolean hasStrips = false;
  public void update(Observable registry, Object updatedDevice) {
    println("Registry changed!");
    if (updatedDevice != null) {
      println("Device change: " + updatedDevice);
    }
    this.hasStrips = true;
  }
}

TestObserver testObserver;

// Physical strip registry
DeviceRegistry registry;
List<Strip> strips = new ArrayList<Strip>();

//
// Controller on the bottom of the screen
//
boolean DRAW_LABELS = false;

// number of roses and number of lights per rose
char NUM_PIXELS = 144;
char EMPTY = 999;

int BRIGHTNESS = 100;  // A percentage

int COLOR_STATE = 0;  // no enum types in processing. Messy

// Color buffers: [BigRose][Pixel][r,g,b]
// Several buffers permits updating only the lights that change color
// May improve performance and reduce flickering
color[][][] curr_buffer = new color[NUM_CHANNELS][NUM_BIG_ROSE][NUM_PIXELS];
color[][][] next_buffer = new color[NUM_CHANNELS][NUM_BIG_ROSE][NUM_PIXELS];
color[][][] morph_buffer = new color[NUM_CHANNELS][NUM_BIG_ROSE][NUM_PIXELS];  // blend of curr + next
color[][] interp_buffer = new color[NUM_BIG_ROSE][NUM_PIXELS];  // combine two channels here

// Timing variables needed to control regular morphing
// Doubled for 2 channels
int[] delay_time = { 10000, 10000 };  // delay time length in milliseconds (dummy initial value)
long[] start_time = { millis(), millis() };  // start time point (in absolute time)
long[] last_time = { start_time[0], start_time[1] };
short[] channel_intensity = { 255, 0 };  // Off = 0, All On = 255 

// Calculated pixel constants for simulator display
boolean UPDATE_VISUALIZER = true;  // turn false for LED-only updates
int SCREEN_SIZE = 300;  // This is the value to change for Screen Size
int SCREEN_WIDTH = SCREEN_SIZE + getBigXoffset(NUM_BIG_ROSE-1);
float BORDER = 0.05; // How much fractional edge between rose and screen
int BORDER_PIX = int(SCREEN_SIZE * BORDER); // Edge in pixels
int ROSE_DIAM = int(SCREEN_SIZE * (1.0 - (2 * BORDER)));  // Rose size
int ROSE_MAP_WIDTH = ROSE_DIAM + getBigXoffset(NUM_BIG_ROSE-1);
float DENSITY = 0.0005; // 'Dottiness' of rose lines. approaching 0 = full line.

// Lookup table to hasten the fill algorithm. Written once, read many times.
char[][] screen_map = new char[ROSE_MAP_WIDTH][ROSE_DIAM];

//
//  Setup
// 
void setup() {
  
  size(SCREEN_WIDTH, SCREEN_SIZE + 50); // 50 for controls
  stroke(0);
  fill(255,255,0);
  
  frameRate(60); // 10? default 60 seems excessive
  
  registry = new DeviceRegistry();
  testObserver = new TestObserver();
  registry.addObserver(testObserver);
  prepareExitHandler();
  strips = registry.getStrips();
  
  colorMode(HSB, 255);  // HSB colors (not RGB)
  
  initializeColorBuffers();  // Stuff curr/next frames with zeros (all black)
  
  background(0, 0, 200);  // gray
  
  for (int i = 0; i < NUM_CHANNELS; i++) {
    _bufs[i] = new StringBuffer();
    _servers[i] = new Server(this, port + i);
    println("server " + i + " listening: " + _servers[i]);
  }
  
  drawGrids();   // need boundaries for flood fill in getScreenMap 
  getScreenMap();  // Map the leaves to the screen pixels to populate look-up table
}

void draw() {
  drawBottomControls();
  pollServer();        // Get messages from python show runner
  update_morph();      // Morph between current frame and next frame
  interpChannels();    // Update the visualizer
  if (UPDATE_VISUALIZER) {
    drawRoses();     // Re-draw frames and triangles
    drawLabels();
  }
  sendDataToLights();  // Dump data into lights
  print_memory_usage();
}

void drawGrids() {
  // Draw each big rose grid
  for (int i = 0; i < NUM_BIG_ROSE; i++) {
    draw_grid(i);
  }
}

// Drawing the rose grid
void draw_grid(int rose_num) {
  color black = color(0,0,0);
  for(float t = 0; t <= 24*PI; t += DENSITY) {
    float r = (ROSE_DIAM/2.0) * cos(12/7.0 * t);  // k/d = 12/7
 
    // Polar to Cartesian conversion
    int x = int(r * cos(t) + ROSE_DIAM/2);
    int y = int(r * sin(t) + ROSE_DIAM/2);
    
    putColor(x + getBigXoffset(rose_num), y, black);
  }
}

int getBigXoffset(int rose_num) {
  return (rose_num * SCREEN_SIZE);
} 

void drawCheckbox(int x, int y, int size, color fill, boolean checked) {
  stroke(0);
  fill(fill);  
  rect(x,y,size,size);
  if (checked) {    
    line(x,y,x+size,y+size);
    line(x+size,y,x,y+size);
  }  
}

void drawBottomControls() {
  // draw a bottom white region
  fill(0,0,255);
  rect(0,SCREEN_SIZE,SCREEN_WIDTH,40);
  
  // draw divider lines
  stroke(0);
  line(140,SCREEN_SIZE,140,SCREEN_SIZE+40);
  line(290,SCREEN_SIZE,290,SCREEN_SIZE+40);
  line(470,SCREEN_SIZE,470,SCREEN_SIZE+40);
  
  // draw checkboxes
  stroke(0);
  fill(0,0,255);
  
  drawCheckbox(20,SCREEN_SIZE+10,20, color(0,0,255), DRAW_LABELS);  // label checkbox
  
  rect(200,SCREEN_SIZE+4,15,15);  // minus brightness
  rect(200,SCREEN_SIZE+22,15,15);  // plus brightness
  
  drawCheckbox(340,SCREEN_SIZE+4,15, color(255,255,255), COLOR_STATE == 1);
  drawCheckbox(340,SCREEN_SIZE+22,15, color(255,255,255), COLOR_STATE == 4);
  drawCheckbox(360,SCREEN_SIZE+4,15, color(87,255,255), COLOR_STATE == 2);
  drawCheckbox(360,SCREEN_SIZE+22,15, color(87,255,255), COLOR_STATE == 5);
  drawCheckbox(380,SCREEN_SIZE+4,15, color(175,255,255), COLOR_STATE == 3);
  drawCheckbox(380,SCREEN_SIZE+22,15, color(175,255,255), COLOR_STATE == 6);
  
  drawCheckbox(400,SCREEN_SIZE+10,20, color(0,0,255), COLOR_STATE == 0);
    
  // draw text labels in 12-point Helvetica
  fill(0);
  textAlign(LEFT);
  PFont f = createFont("Helvetica", 12, true);
  textFont(f, 12);  
  text("Labels", 50, SCREEN_SIZE+25);
  
  text("+", 190, SCREEN_SIZE+16);
  text("-", 190, SCREEN_SIZE+34);
  text("Brightness", 225, SCREEN_SIZE+25);
  textFont(f, 20);
  text(BRIGHTNESS, 150, SCREEN_SIZE+28);
  
  textFont(f, 12);
  text("None", 305, SCREEN_SIZE+16);
  text("All", 318, SCREEN_SIZE+34);
  text("Color", 430, SCREEN_SIZE+25);
  
  int font_size = 12;  // default size
  f = createFont("Helvetica", font_size, true);
  textFont(f, font_size);
}

void mouseClicked() {  
  //println("click! x:" + mouseX + " y:" + mouseY);
  if (mouseX > 20 && mouseX < 40 && mouseY > SCREEN_SIZE+10 && mouseY < SCREEN_SIZE+30) {
    // clicked draw labels button
    DRAW_LABELS = !DRAW_LABELS;
   
  }  else if (mouseX > 200 && mouseX < 215 && mouseY > SCREEN_SIZE+4 && mouseY < SCREEN_SIZE+19) {
    // Bright up checkbox
    if (BRIGHTNESS <= 95) BRIGHTNESS += 5;
    
  } else if (mouseX > 200 && mouseX < 215 && mouseY > SCREEN_SIZE+22 && mouseY < SCREEN_SIZE+37) {
    // Bright down checkbox  
    BRIGHTNESS -= 5;
    if (BRIGHTNESS < 1) BRIGHTNESS = 1;
  
  }  else if (mouseX > 400 && mouseX < 420 && mouseY > SCREEN_SIZE+10 && mouseY < SCREEN_SIZE+30) {
    // No color correction  
    COLOR_STATE = 0;
   
  }  else if (mouseX > 340 && mouseX < 355 && mouseY > SCREEN_SIZE+4 && mouseY < SCREEN_SIZE+19) {
    // None red  
    COLOR_STATE = 1;
   
  }  else if (mouseX > 340 && mouseX < 355 && mouseY > SCREEN_SIZE+22 && mouseY < SCREEN_SIZE+37) {
    // All red  
    COLOR_STATE = 4;
   
  }  else if (mouseX > 360 && mouseX < 375 && mouseY > SCREEN_SIZE+4 && mouseY < SCREEN_SIZE+19) {
    // None blue  
    COLOR_STATE = 2;
   
  }  else if (mouseX > 360 && mouseX < 375 && mouseY > SCREEN_SIZE+22 && mouseY < SCREEN_SIZE+37) {
    // All blue  
    COLOR_STATE = 5;
   
  }  else if (mouseX > 380 && mouseX < 395 && mouseY > SCREEN_SIZE+4 && mouseY < SCREEN_SIZE+19) {
    // None green  
    COLOR_STATE = 3;
   
  }  else if (mouseX > 380 && mouseX < 395 && mouseY > SCREEN_SIZE+22 && mouseY < SCREEN_SIZE+37) {
    // All green  
    COLOR_STATE = 6;
  
  }
}


// Coord class

class Coord {
  public int x, y;
  
  Coord(int x, int y) {
    this.x = x;
    this.y = y;
  }
}

// Fill the coord with a color
void floodFill(Coord coord, byte r, byte p, byte d, color newC, boolean mapping)
{
    int x = coord.x;
    int y = coord.y;
    floodFillUtil(x, y, r, p, d, getColor(x,y), newC, mapping);
}

// Return the color of the x,y pixel
// Adjust for the border
color getColor(int x, int y) {
  return get(x+BORDER_PIX, y+BORDER_PIX);
}

// Adds a point of color at x,y
// Adjust for the border
void putColor(int x, int y, color c) {
  stroke(c);
  point(x+BORDER_PIX, y+BORDER_PIX);
}

// A recursive function to replace previous color 'prevC' at  '(x, y)' 
// and all surrounding pixels of (x, y) with new color 'newC' and
void floodFillUtil(int x, int y, byte r, byte p, byte d, color prevC, color newC, boolean mapping)
{
    char leaf = GetLightFromCoord(r,p,d);
    
    // Base case
    if (x < 0 || x >= ROSE_MAP_WIDTH || y < 0 || y >= ROSE_DIAM) return;
    if (getColor(x,y) != prevC) return;
 
    // Replace the color at (x,y)
    if (mapping) {
      screen_map[x][y] = leaf;      
    }
    putColor(x,y,newC);
 
    // Recur for north, east, south and west
    floodFillUtil(x+1, y, r, p, d, prevC, newC, mapping);
    floodFillUtil(x-1, y, r, p, d, prevC, newC, mapping);
    floodFillUtil(x, y+1, r, p, d, prevC, newC, mapping);
    floodFillUtil(x, y-1, r, p, d, prevC, newC, mapping);
}

//
// drawPixel
//
// Uses a recursive fill from the center of the leaf - slow
//
void drawPixel(byte r, byte p, byte d, color newColor, boolean mapping) {  
  floodFill(GetRoseOffset(r, p, d), r, p, d, newColor, mapping);
}

//
// drawLeaf
//
// Figures out which pixels on the screen correspond to the leaf
// and fills those
// Fast, but assumes a filled screen_map (see getScreenMap)
//
void drawLeaf(byte r, byte p, byte d, color c) {
  int leaf = getLeafNum(r,p,d);
  stroke(c);
  
  for (int x=0; x<ROSE_MAP_WIDTH; x++) {
    for (int y=0; y<ROSE_DIAM; y++) {
      if (screen_map[x][y] == leaf) {
        putColor(x,y,c);
      }
    }
  }
}

//
// getLeafNum
//
int getLeafNum(byte r, byte p, byte d) {
  return ((r * NUM_PIXELS) + (((p * 6) + d) % NUM_PIXELS));
}

//
// Get Rose Offset
//
// Returns the x,y coordinate of an offset point
// Need to add the screen border for actual offset
// Petal is 0-23 number
// distance is 0-11 along the petal with 6 as the outside leaf
//
Coord GetRoseOffset(byte rose, int petal, int distance) {
  petal = (((petal % 5) * 5) + (petal / 5)) % 24; // correct petals to line them up concurrently
  
  float t = PI * 7/12.0 * (petal + ((distance*7)+7)/100.0);
  float r = (ROSE_DIAM/2.0) * sin(12/7.0 * t);  // k/d = 12/7 = 1.7143
  float x = r * cos(t) + ROSE_DIAM/2;
  float y = r * sin(t) + ROSE_DIAM/2;
  // Polar to Cartesian conversion
  return (new Coord(int(x) + getBigXoffset(rose), int(y)));
}

//
// getScreenMap
//
// Recursive flood fill is too memory intensive
// for fast use in the visualizer
//
// Instead, calculate once in set-up and store in a look-up table
// which leaf belongs to each screen pixel 
//
void getScreenMap() {
  // Fill the screen_map with "empty" value
  fillScreen(EMPTY);
  
  for (byte r=0; r < NUM_BIG_ROSE; r++) {
    for (byte p=0; p < 24; p++) {
      for (byte d=0; d < 6; d++) {
        drawPixel(r,p,d, color(255,255,255), true); // Mapping is on (true)
      }
    }
  }
}

//
// fillScreen
//
// populate table with value
//
void fillScreen(char value) {
  for (int x=0; x < ROSE_MAP_WIDTH; x++) {
    for (int y=0; y < ROSE_DIAM; y++) {
      screen_map[x][y] = value;
    }
  }
}

// Raster over the screen_map. Fill each pixel with the appropriate leaf color
// This one-time fill of the screen may be the computationally fastest approach 
void drawRoses() {
  int x,y;
  char pixel;
  
  for (x = 0; x < ROSE_MAP_WIDTH; x++) {
    for (y = 0; y < ROSE_DIAM; y++) {
      pixel = screen_map[x][y];
      if (pixel != EMPTY) {    // a leaf spot
        putColor(x,y, interp_buffer[pixel / NUM_PIXELS][pixel % NUM_PIXELS]);
      }
    }
  }
}

/* DEPRECATED 
void setCellColor(color c, byte r, int i) {
  if (i >= NUM_PIXELS) {
    println("invalid LED number: i only have " + NUM_PIXELS + " LEDs");
    return;
  }
  if (r >= NUM_BIG_ROSE) {
    println("invalid rose number: i only have " + NUM_BIG_ROSE + " Roses");
    return;
  }
  
  interp_buffer[r][i] = c;
}
*/

//
// drawLabels
//
void drawLabels() {
  for (byte i = 0; i < NUM_BIG_ROSE; i++) {
    draw_label(i);
  }
}

// Drawing the rose grid
void draw_label(byte r) {
  if (!DRAW_LABELS) return;
  
  String text_coord;
  Coord coord;
  
  fill(0,0,50);  // Gray
  textAlign(CENTER);
  PFont f = createFont("Helvetica", 8, true);
  textFont(f, 8); 
  
  for (int p = 0; p < 24; p++) {
    for (int d = 0; d < 6; d++) {
      text_coord = String.format("%d,%d", p, d);
      coord = GetRoseOffset(r,p,d);
      text(text_coord, coord.x + BORDER_PIX, coord.y + BORDER_PIX);
    }
  }
}

//
// Get Light From Coord
//
// Algorithm to convert (petal,distance) coordinate into an LED number
char GetLightFromCoord(byte r, byte p, byte d) {
  int LED = (((5-d)/2)*48) + (p*2) + ((d+1)%2);
  
  if (d == 2 || d == 3) {  // Middle two rings of LEDs 48-95
    LED = LED+1;           // Shift the ring due to wiring
    if (LED >= 96) LED -= 48;
  }
  
  if (d <= 1) {   // Inner two rings of LEDs 96-143
    LED = LED+4;  // Shift the ring due to wiring
    if (LED >= 144) LED -= 48;
  }
  return char(LED + (r * NUM_PIXELS));  // Overloading LED with Big Rose
}

//
//  Server Routines
//
void pollServer() {
  // Read 2 different server ports into 2 buffers - keep channels separated
  for (int i = 0; i < NUM_CHANNELS; i++) {
    try {
      Client c = _servers[i].available();
      // append any available bytes to the buffer
      if (c != null) {
        _bufs[i].append(c.readString());
      }
      // process as many lines as we can find in the buffer
      int ix = _bufs[i].indexOf("\n");
      while (ix > -1) {
        String msg = _bufs[i].substring(0, ix);
        msg = msg.trim();
        processCommand(msg);
        _bufs[i].delete(0, ix+1);
        ix = _bufs[i].indexOf("\n");
      }
    } catch (Exception e) {
      println("exception handling network command");
      e.printStackTrace();
    }
  }  
}

//
// With DUAL shows: 
// 1. all commands must start with either a '0' or '1'
// 2. Followed by either
//     a. X = Finish a morph cycle (clean up by pushing the frame buffers)
//     b. D(int) = delay for int milliseconds (but keeping morphing)
//     c. I(short) = channel intensity (0 = off, 255 = all on)
//     d. Otherwise, process 5 integers as (s,i, r,g,b)
//
//
void processCommand(String cmd) {
  if (cmd.length() < 2) { return; }  // Discard erroneous stub characters
  byte channel = (cmd.charAt(0) == '0') ? (byte)0 : (byte)1 ;  // First letter indicates Channel 0 or 1
  cmd = cmd.substring(1, cmd.length());  // Strip off first-letter Channel indicator
  
  if (cmd.charAt(0) == 'X') {  // Finish the cycle
    finishCycle(channel);
  } else if (cmd.charAt(0) == 'D') {  // Get the delay time
    delay_time[channel] = Integer.valueOf(cmd.substring(1, cmd.length()));
  } else if (cmd.charAt(0) == 'I') {  // Get the intensity
    channel_intensity[channel] = Integer.valueOf(cmd.substring(1, cmd.length())).shortValue();
  } else {  
    processPixelCommand(channel, cmd);  // Pixel command
  }
}

// 5 comma-separated numbers for triangle, pixel, h, s, v
Pattern cmd_pattern = Pattern.compile("^\\s*(\\d+),(\\d+),(\\d+),(\\d+),(\\d+)\\s*$");

void processPixelCommand(byte channel, String cmd) {
  Matcher m = cmd_pattern.matcher(cmd);
  if (!m.find()) {
    //println(cmd);
    println("ignoring input for " + cmd);
    return;
  }
  byte r    =    Byte.valueOf(m.group(1));
  int p     = Integer.valueOf(m.group(2));
  int h     = Integer.valueOf(m.group(3));
  int s     = Integer.valueOf(m.group(4));
  int v     = Integer.valueOf(m.group(5));
  
  next_buffer[channel][r][p] = color( (short)h, (short)s, (short)v );  
//  println(String.format("setting channel %d pixel:%d,%d to h:%d, s:%d, v:%d", channel, s, i, h, s, v));
}

//
// Finish Cycle
//
// Get ready for the next morph cycle by morphing to the max and pushing the frame buffer
//
void finishCycle(byte channel) {
  morph_frame(channel, 1.0);  // May work after all
  pushColorBuffer(channel);
  start_time[channel] = millis();  // reset the clock
}

//
// Update Morph
//
void update_morph() {
  // Fractional morph over the span of delay_time
  for (byte channel = 0; channel < NUM_CHANNELS; channel++) {
    last_time[channel] = millis();  // update clock
    float fract = (last_time[channel] - start_time[channel]) / (float)delay_time[channel];
    if (is_channel_active(channel) && fract <= 1.0) {
      morph_frame(channel, fract);
    }
  }
}

//
// Is Channel Active
//
boolean is_channel_active(int channel) {
  return (channel_intensity[channel] > 0);
}

/////  Routines to interact with the Lights

//
// Interpolate Channels
//
// Interpolate between the 2 channels
// Push the interpolated results on to the simulator 
//
void interpChannels() {
  if (!is_channel_active(0)) {
    pushOnlyOneChannel(1);
  } else if (!is_channel_active(1)) {
    pushOnlyOneChannel(0);
  } else {
    float fract = (float)channel_intensity[0] / (channel_intensity[0] + channel_intensity[1]);
    morphBetweenChannels(fract);
  }
}

//
// pushOnlyOneChannel - push the morph_channel to the simulator
//
void pushOnlyOneChannel(int channel) {
  color col;
  for (byte r = 0; r < NUM_BIG_ROSE; r++) {
    for (int p = 0; p < NUM_PIXELS; p++) {
      col = adjColor(morph_buffer[channel][r][p]);
      // roseGrid[r].setCellColor(col, p);
      interp_buffer[r][p] = col;
    }
  }
}

//
// morphBetweenChannels - interpolate the morph_channel on to the simulator
//
void morphBetweenChannels(float fract) {
  color col;
  for (byte r = 0; r < NUM_BIG_ROSE; r++) {
    for (int p = 0; p < NUM_PIXELS; p++) {
      col = adjColor(interp_color(morph_buffer[1][r][p], morph_buffer[0][r][p], fract));
      // triGrid[t].setCellColor(col, p);
      interp_buffer[r][p] = col;
    }
  }
}

// Adjust color for brightness and hue
color adjColor(color c) {
  return adj_brightness(colorCorrect(c));
}

// Convert hsb color (0-255) to hsb (0-1.0) and then to rgb (0-255)
//   warning: it's messy
color hsb_to_rgb(color c) {
  int color_int = Color.HSBtoRGB(hue(c) / 255.0,  // 255?
                                 saturation(c) / 255.0, 
                                 brightness(c) / 255.0);
  return color((color_int & 0x00FF0000) >> 16, 
               (color_int & 0x0000FF00) >> 8, 
               (color_int & 0x000000FF));
}

//
//  Routines for the strip buffer
//

void sendDataToLights() {
  byte r;
  int p;
  
  if (testObserver.hasStrips) {   
    registry.startPushing();
    registry.setExtraDelay(0);
    registry.setAutoThrottle(true);
    registry.setAntiLog(true);    
    
    List<Strip> strips = registry.getStrips();
    r = 0;
    
    for (Strip strip : strips) {      
      for (p = 0; p < NUM_PIXELS; p++) {
        strip.setPixel(hsb_to_rgb(interp_buffer[r][p]), p);
      }
      r++;
      if (r >= NUM_BIG_ROSE) break;  // Prevents buffer overflow
    }
  }
}

private void prepareExitHandler () {

  Runtime.getRuntime().addShutdownHook(new Thread(new Runnable() {

    public void run () {

      System.out.println("Shutdown hook running");

      List<Strip> strips = registry.getStrips();
      for (Strip strip : strips) {
        for (int i = 0; i < strip.getLength(); i++)
          strip.setPixel(#000000, i);
      }
      for (int i=0; i<100000; i++)
        Thread.yield();
    }
  }
  ));
}

//
//  Fractional morphing between current and next frame - sends data to lights
//
//  fract is an 0.0 - 1.0 fraction towards the next frame
//
void morph_frame(byte c, float fract) {
  for (byte r = 0; r < NUM_BIG_ROSE; r++) {
    for (int p = 0; p < NUM_PIXELS; p++) {
      morph_buffer[c][r][p] = interp_color(curr_buffer[c][r][p], next_buffer[c][r][p], fract);   
    }
  }
}

color adj_brightness(color c) {
  // Adjust only the 3rd brightness channel
  return color(hue(c), saturation(c), brightness(c) * BRIGHTNESS / 100);
}

color colorCorrect(color c) {
  short new_hue;
  
  switch(COLOR_STATE) {
    case 1:  // no red
      new_hue = map_range(hue(c), 40, 200);
      break;
    
    case 2:  // no green
      new_hue = map_range(hue(c), 120, 45);
      break;
    
    case 3:  // no blue
      new_hue = map_range(hue(c), 200, 120);
      break;
    
    case 4:  // all red
      new_hue = map_range(hue(c), 200, 40);
      break;
    
    case 5:  // all green
      new_hue = map_range(hue(c), 40, 130);
      break;
    
    case 6:  // all blue
      new_hue = map_range(hue(c), 120, 200);
      break;
    
    default:  // all colors
      new_hue = (short)hue(c);
      break;
  }
  return color(new_hue, saturation(c), brightness(c));
}

//
// map_range - map a hue (0-255) to a smaller range (start-end)
//
short map_range(float hue, int start, int end) {
  int range = (end > start) ? end - start : (end + 256 - start) % 256 ;
  return (short)((start + ((hue / 255.0) * range)) % 256);
}

void initializeColorBuffers() {
  for (int c = 0; c < NUM_CHANNELS; c++) {
    fill_black_one_channel(c);
  }
}

void fill_black_one_channel(int c) {
  color black = color(0,0,0); 
  for (byte r = 0; r < NUM_BIG_ROSE; r++) {
    for (int p = 0; p < NUM_PIXELS; p++) {
      curr_buffer[c][r][p] = black;
      next_buffer[c][r][p] = black;
    }
  }
}

void pushColorBuffer(byte c) {
  for (byte r = 0; r < NUM_BIG_ROSE; r++) {
    for (int p = 0; p < NUM_PIXELS; p++) {
      curr_buffer[c][r][p] = next_buffer[c][r][p];
    }
  }
}

void print_memory_usage() {
  long maxMemory = Runtime.getRuntime().maxMemory();
  long allocatedMemory = Runtime.getRuntime().totalMemory();
  long freeMemory = Runtime.getRuntime().freeMemory();
  int inUseMb = int(allocatedMemory / 1000000);
  
  if (inUseMb > 80) {
    println("Memory in use: " + inUseMb + "Mb");
  }  
}

color interp_color(color c1, color c2, float fract) {
 // standard lerpColor interpolation does not work well
 // for HSV colors if one color is black
 if (is_black(c1) && is_black(c2)) {
   return c1;
 } else if (is_black(c1)) {
  return color(hue(c2), saturation(c2), brightness(c2) * fract);
 } else if (is_black(c2)) {
  return color(hue(c1), saturation(c1), brightness(c1) * (1.0 - fract));
 } else {
   return color(lerp(hue(c1), hue(c2), fract),
                lerp(saturation(c1), saturation(c2), fract),
                lerp(brightness(c1), brightness(c2), fract));
 }
} 

boolean is_black(color c) {
  return (hue(c) == 0 && saturation(c) == 0 && brightness(c) == 0);
}
