/*
 * MASTER INTERFACE CODE v3: Bio-Heat Reactor
 * ------------------------------------------
 * COMMAND LIST:
 * - "HEAT ON"   -> Activate Heater Control
 * - "HEAT OFF"  -> Force Heater OFF
 * - "T 45"      -> Set Target Temp to 45 deg
 * - "PUMP ON"   -> Start Air Pump (4h Timer)
 * - "PUMP OFF"  -> Stop Air Pump
 * - "PUMP 80"   -> Set Pump Speed to 80%
 */

#include <Arduino.h>

// --- PINS ---
const int PIN_NTC_BULK = 32;   // Innen
const int PIN_NTC_HEATER = 33; // Aussen
const int PIN_SSR = 25;        // Heizung
const int PIN_PUMP_1 = 26;     // Pumpe A
const int PIN_PUMP_2 = 27;     // Pumpe B
const int PIN_LED = 2;         // Status LED

// --- KALIBRIERUNG (Ref 21.65 °C) ---
const float R_REF_BULK = 4639.0;
const float R_REF_HEATER = 4647.0;
const float OFFSET_BULK = -6.66;     
const float OFFSET_HEATER = -6.56; 
const float BETA = 3950.0;
const float R_NOMINAL = 10000.0;
const float T_NOMINAL = 298.15;

// --- EINSTELLUNGEN (Startwerte) ---
float targetTemp = 35.0;       // Standard-Startwert
int pumpSpeedPercent = 0;      // Start: Pumpe aus
bool heaterEnabled = false;    // Start: Heizung aus (Sicherheit)
bool pumpEnabled = false;      // Start: Pumpe aus

// --- SICHERHEIT ---
const float SAFETY_LIMIT = 75.0;
const float OVERSHOOT_BUFFER = 0.5; // Stoppt 0.5° vor Ziel (Anti-Overshoot)
const float HYSTERESIS = 0.2;
const unsigned long MAX_PUMP_RUNTIME = 4 * 60 * 60 * 1000UL; // 4 Stunden

// --- TIMER ---
unsigned long pumpStartTime = 0;
unsigned long lastPrintTime = 0;

void setup() {
  Serial.begin(115200);
  
  pinMode(PIN_SSR, OUTPUT);
  pinMode(PIN_LED, OUTPUT);
  digitalWrite(PIN_SSR, LOW);
  
  // Pumpe Setup (ESP32 v3.0)
  ledcAttach(PIN_PUMP_1, 5000, 8);
  ledcAttach(PIN_PUMP_2, 5000, 8);
  
  analogReadResolution(12);

  Serial.println("--- SYSTEM BEREIT (v3) ---");
  Serial.println("Waiting for commands...");
  Serial.println("Time_Sec,T_Innen,T_Aussen,Ziel,Heizung,Pumpe_Speed"); 
}

// --- Temperatur lesen ---
float getTemp(int pin, float r_ref, float offset) {
  float sum = 0; int n = 0;
  for (int i=0; i<30; i++) { 
    int raw = analogRead(pin);
    if (raw > 0 && raw < 4095) {
      float r = r_ref * ((float)raw / (4095.0 - (float)raw));
      sum += r; n++;
    }
    delay(1);
  }
  if (n==0) return -999.0;
  float avg = sum/n;
  float t = 1.0 / (log(avg / R_NOMINAL) / BETA + 1.0 / T_NOMINAL);
  return (t - 273.15) + offset;
}

// --- Pumpe steuern ---
void updatePump() {
  if (pumpEnabled) {
    int pwm = map(pumpSpeedPercent, 0, 100, 0, 255);
    // Safe Start: Mindestens 40%
    if (pumpSpeedPercent > 0 && pumpSpeedPercent < 40) pwm = map(40, 0, 100, 0, 255); 
    
    ledcWrite(PIN_PUMP_1, pwm);
    ledcWrite(PIN_PUMP_2, 0);
  } else {
    ledcWrite(PIN_PUMP_1, 0);
    ledcWrite(PIN_PUMP_2, 0);
  }
}

void loop() {
  unsigned long currentMillis = millis();

  // --- 1. BEFEHLE LESEN ---
  if (Serial.available() > 0) {
    String input = Serial.readStringUntil('\n');
    input.trim(); 
    input.toUpperCase(); // Alles Grossbuchstaben

    // --- HEIZUNG ---
    if (input == "HEAT ON" || input == "H ON") {
      heaterEnabled = true;
      Serial.println(">> OK: HEAT ON (Regelung aktiv)");
    }
    else if (input == "HEAT OFF" || input == "H OFF") {
      heaterEnabled = false;
      digitalWrite(PIN_SSR, LOW); // SOFORT AUS
      Serial.println(">> OK: HEAT OFF (System inaktiv)");
    }

    // --- PUMPE ---
    else if (input == "PUMP ON" || input == "START") {
      pumpEnabled = true;
      pumpStartTime = millis(); 
      updatePump();
      Serial.println(">> OK: PUMP ON (4h Timer Start)");
    }
    else if (input == "PUMP OFF" || input == "STOP") {
      pumpEnabled = false;
      updatePump();
      Serial.println(">> OK: PUMP OFF");
    }
    // "PUMP 50"
    else if (input.startsWith("PUMP ") || input.startsWith("P ")) {
      int spaceIndex = input.indexOf(' ');
      if (spaceIndex != -1) {
        String valStr = input.substring(spaceIndex + 1);
        pumpSpeedPercent = valStr.toInt();
        if (pumpSpeedPercent > 100) pumpSpeedPercent = 100;
        if (pumpSpeedPercent < 0) pumpSpeedPercent = 0;
        
        if (pumpEnabled) updatePump();
        
        Serial.print(">> OK: PUMP SPEED "); 
        Serial.print(pumpSpeedPercent); Serial.println("%");
      }
    }

     else if (input.startsWith("T")) {
      String valStr = (input.startsWith("T ")) ? input.substring(2) : input.substring(1);
      float newT = valStr.toFloat();
      if (newT > 0 && newT < 80) {
        targetTemp = newT;
        Serial.print(">> OK: TARGET TEMP SET TO "); Serial.println(targetTemp);
      }
    }
  }

  // --- 2. MESSEN ---
  float tBulk = getTemp(PIN_NTC_BULK, R_REF_BULK, OFFSET_BULK);
  float tHeater = getTemp(PIN_NTC_HEATER, R_REF_HEATER, OFFSET_HEATER);

  // --- 3. SICHERHEIT ---
  if (tBulk > SAFETY_LIMIT || tHeater > SAFETY_LIMIT) {
    heaterEnabled = false; pumpEnabled = false;
    digitalWrite(PIN_SSR, LOW); updatePump();
    Serial.println("!!! ALARM: UEBERHITZUNG !!!");
    while(1);
  }

  // 4h Timer
  if (pumpEnabled && (currentMillis - pumpStartTime > MAX_PUMP_RUNTIME)) {
    pumpEnabled = false;
    updatePump();
    Serial.println(">> INFO: 4h Limit. Pumpe STOP.");
  }

  // --- 4. REGELUNG ---
  bool ssrState = false;
  if (heaterEnabled) {
    float maxTemp = (tBulk > tHeater) ? tBulk : tHeater;
    float stopTemp = targetTemp - OVERSHOOT_BUFFER;

    if (maxTemp < (stopTemp - HYSTERESIS)) {
      digitalWrite(PIN_SSR, HIGH);
      ssrState = true;
    } else if (maxTemp > stopTemp) {
      digitalWrite(PIN_SSR, LOW);
      ssrState = false;
    } else {
      ssrState = digitalRead(PIN_SSR);
    }
  } else {
    digitalWrite(PIN_SSR, LOW); // HEAT OFF -> Zwangsaus
    ssrState = false;
  }
  
  digitalWrite(PIN_LED, ssrState ? HIGH : LOW);

  // --- 5. CSV OUTPUT ---
  if (currentMillis - lastPrintTime >= 1000) {
    lastPrintTime = currentMillis;
    Serial.print(currentMillis / 1000); Serial.print(",");
    Serial.print(tBulk, 2); Serial.print(",");
    Serial.print(tHeater, 2); Serial.print(",");
    Serial.print(targetTemp, 1); Serial.print(",");
    Serial.print(ssrState ? 1 : 0); Serial.print(",");
    Serial.println(pumpEnabled ? pumpSpeedPercent : 0);
  }
}// --- TEMPERATUR ("T 40") ---
   