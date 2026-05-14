/* * AUTONOMOUS REACTOR v7 (SAFETY EDITION)
 * Core Logic: 50.0 °C Target | Emergency Stop > 75.0 °C
 */

#include <Arduino.h>
#include <FS.h>
#include <LittleFS.h> 

// --- PIN CONFIGURATION ---
const int PIN_NTC_BULK = 32;   
const int PIN_NTC_HEATER = 33; 
const int PIN_SSR = 25;        
const int PIN_PUMP_1 = 26;     
const int PIN_PUMP_2 = 27;     
const int PIN_LED = 2;         

// --- CALIBRATION ---
const float R_REF_BULK = 4639.0;
const float R_REF_HEATER = 4647.0;
const float OFFSET_BULK = -6.66;     
const float OFFSET_HEATER = -6.56; 
const float BETA = 3950.0;
const float R_NOMINAL = 10000.0;
const float T_NOMINAL = 298.15;

// --- OPERATIONAL SETTINGS ---
const float TARGET_TEMP = 50.0;       
const int PUMP_SPEED = 75;            

// --- SAFETY LIMITS ---
const float TEMP_MAX_LIMIT = 75.0;    // Emergency shut-off threshold
const float TEMP_REARM_LIMIT = 25.0;  // System restart threshold
const float TEMP_MIN_VALID = 0.0;     // Sensor fault detection (low)
const float TEMP_MAX_VALID = 110.0;   // Sensor fault detection (high)

// --- TIMING ---
const unsigned long CONTROL_INTERVAL = 1000UL;  // 1 Hz
const unsigned long LOG_INTERVAL = 20000UL;     // 20 sec
const unsigned long TIME_PUMP_ON = 30UL * 60UL * 1000UL;  
const unsigned long TIME_PUMP_OFF = 30UL * 60UL * 1000UL; 

// --- GLOBAL STATE ---
unsigned long lastControlTime = 0;
unsigned long lastLogTime = 0;
unsigned long lastCycleSwitch = 0;
bool isPumpPhase = true; 
bool ssrState = false;
bool emergencyMode = false; 

void setup() {
  Serial.begin(115200);
  pinMode(PIN_SSR, OUTPUT);
  pinMode(PIN_LED, OUTPUT);
  digitalWrite(PIN_SSR, LOW);
  
  ledcAttach(PIN_PUMP_1, 5000, 8);
  ledcAttach(PIN_PUMP_2, 5000, 8);
  analogReadResolution(12);

  if(!LittleFS.begin(true)) Serial.println("Error: LittleFS failed");

  lastCycleSwitch = millis();
  
  for(int i=0; i<5; i++) {
    digitalWrite(PIN_LED, HIGH); delay(100);
    digitalWrite(PIN_LED, LOW); delay(100);
  }
}

float getTemp(int pin, float r_ref, float offset) {
  float sum = 0; int n = 0;
  for (int i=0; i<20; i++) { 
    int raw = analogRead(pin);
    if (raw > 0 && raw < 4095) {
      float r = r_ref * ((float)raw / (4095.0 - (float)raw));
      sum += r; n++;
    } delay(2);
  }
  if (n==0) return -999.0; 
  float avg = sum/n;
  float t = 1.0 / (log(avg / R_NOMINAL) / BETA + 1.0 / T_NOMINAL);
  return (t - 273.15) + offset;
}

void setPump(int p) {
  int pwm = (p > 0 && p < 40) ? map(40,0,100,0,255) : map(p,0,100,0,255);
  ledcWrite(PIN_PUMP_1, (p==0)?0:pwm);
  ledcWrite(PIN_PUMP_2, 0);
}

void logToMemory(float t1, float t2, int heat, int pump, int err) {
  File f = LittleFS.open("/data.csv", "a"); 
  if (f) {
    f.print(millis()/1000); f.print(",");
    f.print(t1, 2); f.print(",");
    f.print(t2, 2); f.print(",");
    f.print(heat); f.print(",");
    f.print(pump); f.print(",");
    f.println(err); 
    f.close();
  }
}

void loop() {
  unsigned long now = millis();

  // --- SERIAL COMMAND HANDLING ---
  if (Serial.available()) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim(); cmd.toUpperCase();
    
    if (cmd == "DATA") { 
      Serial.println("\n--- START DATA DUMP ---");
      File f = LittleFS.open("/data.csv", "r");
      if (f) {
        while(f.available()) Serial.write(f.read());
        f.close();
      }
      Serial.println("\n--- END DATA DUMP ---");
    }
    else if (cmd == "DELETE") {
      LittleFS.remove("/data.csv");
      Serial.println(">> MEMORY CLEARED.");
    }
    else if (cmd == "RESET") {
      emergencyMode = false;
      Serial.println(">> ALARM RESET.");
    }
  }

  // --- 1 Hz CONTROL LOOP ---
  if (now - lastControlTime >= CONTROL_INTERVAL) {
    lastControlTime = now;

    float tBulk = getTemp(PIN_NTC_BULK, R_REF_BULK, OFFSET_BULK);
    float tHeater = getTemp(PIN_NTC_HEATER, R_REF_HEATER, OFFSET_HEATER);
    float maxT = (tBulk > tHeater) ? tBulk : tHeater;

    // Safety Checks
    if (tBulk < TEMP_MIN_VALID || tBulk > TEMP_MAX_VALID || 
        tHeater < TEMP_MIN_VALID || tHeater > TEMP_MAX_VALID) emergencyMode = true; 
    
    if (maxT > TEMP_MAX_LIMIT) emergencyMode = true;

    if (emergencyMode && maxT < TEMP_REARM_LIMIT && maxT > TEMP_MIN_VALID) emergencyMode = false;

    if (emergencyMode) {
      digitalWrite(PIN_SSR, LOW);
      setPump(0);
      ssrState = false;
      digitalWrite(PIN_LED, !digitalRead(PIN_LED)); 
    } 
    else {
      // Aeration Cycle
      if (isPumpPhase) {
        setPump(PUMP_SPEED);
        if (now - lastCycleSwitch > TIME_PUMP_ON) {
          isPumpPhase = false; lastCycleSwitch = now;
        }
      } else {
        setPump(0);
        if (now - lastCycleSwitch > TIME_PUMP_OFF) {
          isPumpPhase = true; lastCycleSwitch = now;
        }
      }

      // Heating Control (Hysteresis)
      if (maxT < (TARGET_TEMP - 0.2)) {
        digitalWrite(PIN_SSR, HIGH);
        ssrState = true;
      } else if (maxT > TARGET_TEMP) {
        digitalWrite(PIN_SSR, LOW);
        ssrState = false;
      }
      digitalWrite(PIN_LED, ssrState);
    }
  }

  // --- 20s LOGGING CYCLE ---
  if (now - lastLogTime >= LOG_INTERVAL) {
    lastLogTime = now;
    float t1 = getTemp(PIN_NTC_BULK, R_REF_BULK, OFFSET_BULK);
    float t2 = getTemp(PIN_NTC_HEATER, R_REF_HEATER, OFFSET_HEATER);
    logToMemory(t1, t2, ssrState ? 1 : 0, isPumpPhase ? PUMP_SPEED : 0, emergencyMode ? 1 : 0);
  }
}