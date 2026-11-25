/*
 * =============================================================================
 *  VFD-Aquatec  –  ESP32  –  vfd_ble_sensors_sim.ino  (FIXED)
 * =============================================================================
 *  FIXES:
 *   - update_simulated_sensors() réagit aux commandes reçues du téléphone
 *   - La démo auto est DESACTIVEE par défaut (demo_auto = false)
 *   - Commandes reçues via BLE (START/STOP/FREQ/MODE) mettent à jour
 *     stm_freq et stm_running directement → simulation cohérente
 *   - Envoi trame STM32 fake pour que l'app Flutter mette à jour le gauge
 * =============================================================================
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <HardwareSerial.h>

#define SERVICE_UUID   "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHAR_UUID_RX   "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHAR_UUID_TX   "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
#define DEVICE_NAME    "VFD-Aquatec"

HardwareSerial STM32_Serial(2);

/* ---- Simulation ---------------------------------------------------------- */
float    sim_tempC   = 22.0f;
float    sim_bar     = 0.0f;
float    sim_flowLpm = 0.0f;

// FIX: ces variables sont maintenant contrôlées par les commandes BLE
float    stm_freq    = 0.0f;
uint8_t  stm_running = 0;
float    stm_target  = 0.0f;   // fréquence cible reçue via FREQ xx

unsigned long lastSensorSim = 0;

/* ---- BLE ----------------------------------------------------------------- */
BLEServer         *pServer       = nullptr;
BLECharacteristic *pTxChar       = nullptr;
bool               ble_connected = false;
String             stm_buf       = "";

/* ========================================================================== */
/*  BLE send chunked                                                          */
/* ========================================================================== */
void bleSend(const String &s)
{
    if (!ble_connected || s.length() == 0) return;
    const int MTU = 20;
    int len = s.length(), sent = 0;
    while (sent < len)
    {
        int chunk = min(MTU, len - sent);
        pTxChar->setValue((uint8_t *)(s.c_str() + sent), chunk);
        pTxChar->notify();
        sent += chunk;
        delay(10);
    }
}

/* ========================================================================== */
/*  Simulation capteurs – réagit à stm_freq / stm_running                     */
/* ========================================================================== */
void update_simulated_sensors()
{
    // FIX: rampe douce de stm_freq vers stm_target (simule la rampe STM32)
    if (stm_running && stm_freq < stm_target)
    {
        stm_freq += 0.8f;   // ~0.8 Hz par tick de 2s → ~60s pour 0→50Hz
        if (stm_freq > stm_target) stm_freq = stm_target;
    }
    else if (!stm_running && stm_freq > 0.0f)
    {
        stm_freq -= 1.0f;   // décélération
        if (stm_freq < 0.0f) stm_freq = 0.0f;
    }

    float ratio = stm_freq / 50.0f;

    // Débit linéaire
    float target_flow = stm_running ? (ratio * 18.0f) : 0.0f;
    sim_flowLpm += (target_flow - sim_flowLpm) * 0.15f;
    if (sim_flowLpm < 0.01f) sim_flowLpm = 0.0f;

    // Pression quadratique (loi pompe centrifuge)
    float target_bar = stm_running ? (ratio * ratio * 3.2f) : 0.0f;
    sim_bar += (target_bar - sim_bar) * 0.12f;
    if (sim_bar < 0.005f) sim_bar = 0.0f;

    // Température avec inertie thermique
    float target_temp = stm_running ? (22.0f + ratio * 43.0f) : 22.0f;
    sim_tempC += (target_temp - sim_tempC) * 0.02f;
}

/* ========================================================================== */
/*  Parse commandes BLE reçues du téléphone                                   */
/*  Met à jour stm_running / stm_target directement (sans STM32)              */
/* ========================================================================== */
void handle_ble_command(const String &cmd)
{
    String c = cmd;
    c.trim();
    c.toUpperCase();

    if (c == "START")
    {
        if (stm_target >= 5.0f)
        {
            stm_running = 1;
            Serial.print("[CMD] START → rampe vers ");
            Serial.print(stm_target); Serial.println(" Hz");
            // Réponse fake STM32 vers téléphone
            char buf[64];
            snprintf(buf, sizeof(buf), "[OK] Demarrage rampe vers %.1f Hz...\r\n", stm_target);
            bleSend(String(buf));
        }
        else
        {
            bleSend("[ERR] Tape FREQ xx d abord (min 5 Hz)\r\n");
        }
    }
    else if (c == "STOP")
    {
        stm_running = 0;
        stm_target  = 0.0f;
        Serial.println("[CMD] STOP");
        bleSend("[OK] Deceleration...\r\n");
        bleSend("[OK] Moteur ARRETE\r\n");
    }
    else if (c.startsWith("FREQ "))
    {
        float f = c.substring(5).toFloat();
        if (f >= 5.0f && f <= 50.0f)
        {
            stm_target = f;
            char buf[48];
            snprintf(buf, sizeof(buf), "[OK] Freq cible = %.1f Hz\r\n", f);
            bleSend(String(buf));
            Serial.print("[CMD] FREQ → "); Serial.println(f);
            // Si moteur tourne déjà → rampe vers nouvelle freq
            if (stm_running) {
                // stm_freq continuera vers stm_target dans update_simulated_sensors
            }
        }
        else { bleSend("[ERR] Frequence hors limites (5-50 Hz)\r\n"); }
    }
    else if (c == "MODE 1")
    {
        stm_target  = 50.0f;
        stm_running = 1;
        bleSend("[MODE 1] AUTO - Demarrage 50 Hz\r\n");
        Serial.println("[CMD] MODE 1");
    }
    else if (c == "MODE 2")
    {
        bleSend("[MODE 2] MANUEL - en attente de commandes\r\n");
        Serial.println("[CMD] MODE 2");
    }
    else if (c == "MODE 3")
    {
        bleSend("[MODE 3] SEQUENCE - construis ta sequence\r\n");
        bleSend("  ADD <Hz> <sec>  LIST  CLEAR  GO  STOP\r\n");
        Serial.println("[CMD] MODE 3");
    }
    else if (c == "STATUS")
    {
        char buf[128];
        snprintf(buf, sizeof(buf),
                 "-----------------------------\r\n"
                 "Moteur     : %s\r\n"
                 "Freq reelle: %.1f Hz\r\n"
                 "Freq cible : %.1f Hz\r\n"
                 "Temp       : %.1f C\r\n"
                 "Pression   : %.2f bar\r\n"
                 "Debit      : %.2f L/min\r\n"
                 "-----------------------------\r\n",
                 stm_running ? "EN MARCHE" : "ARRETE",
                 stm_freq, stm_target,
                 sim_tempC, sim_bar, sim_flowLpm);
        bleSend(String(buf));
    }
    else if (c == "TELEM ON")  { bleSend("[OK] Telemetrie ON\r\n"); }
    else if (c == "TELEM OFF") { bleSend("[OK] Telemetrie OFF\r\n"); }
    else
    {
        // Tout le reste (ADD, LIST, GO, etc.) → relay vers STM32 si branché
        STM32_Serial.print(cmd);
        STM32_Serial.print("\r\n");
    }
}

/* ========================================================================== */
/*  BLE Callbacks                                                             */
/* ========================================================================== */
class ServerCallbacks : public BLEServerCallbacks
{
    void onConnect(BLEServer *pSrv) override
    {
        ble_connected = true;
        Serial.println("[BLE] Telephone connecte");
        bleSend("VFD-Aquatec connecte\r\n"
                "MODE 1=Auto  MODE 2=Manuel  MODE 3=Sequence\r\n"
                "STATUS  TELEM ON/OFF\r\n");
    }
    void onDisconnect(BLEServer *pSrv) override
    {
        ble_connected = false;
        Serial.println("[BLE] Deconnecte");
        delay(500);
        pSrv->startAdvertising();
    }
};

class RxCallbacks : public BLECharacteristicCallbacks
{
    void onWrite(BLECharacteristic *pChar) override
    {
        String rxVal = pChar->getValue().c_str();
        rxVal.trim();
        if (rxVal.length() == 0) return;
        Serial.print("[BLE RX] "); Serial.println(rxVal);
        handle_ble_command(rxVal);
    }
};

/* ========================================================================== */
/*  Setup                                                                     */
/* ========================================================================== */
void setup()
{
    Serial.begin(115200);
    STM32_Serial.begin(115200, SERIAL_8N1, 16, 17);
    delay(500);
    lastSensorSim = millis();

    Serial.println("[BOOT] VFD-Aquatec BLE + Capteurs SIMULES (fixed)");

    BLEDevice::init(DEVICE_NAME);
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new ServerCallbacks());

    BLEService *pService = pServer->createService(SERVICE_UUID);

    pTxChar = pService->createCharacteristic(
                  CHAR_UUID_TX, BLECharacteristic::PROPERTY_NOTIFY);
    pTxChar->addDescriptor(new BLE2902());

    BLECharacteristic *pRxChar = pService->createCharacteristic(
                                     CHAR_UUID_RX,
                                     BLECharacteristic::PROPERTY_WRITE |
                                     BLECharacteristic::PROPERTY_WRITE_NR);
    pRxChar->setCallbacks(new RxCallbacks());

    pService->start();
    BLEAdvertising *pAdv = BLEDevice::getAdvertising();
    pAdv->addServiceUUID(SERVICE_UUID);
    pAdv->setScanResponse(true);
    pAdv->setMinPreferred(0x06);
    BLEDevice::startAdvertising();

    Serial.println("[BLE] Advertising...");
}

/* ========================================================================== */
/*  Loop                                                                      */
/* ========================================================================== */
void loop()
{
    unsigned long now = millis();

    /* ---- Simulation + envoi TELEM toutes les 2 s ----------------------- */
    if (now - lastSensorSim >= 2000)
    {
        lastSensorSim = now;
        update_simulated_sensors();

        Serial.print("[SIM] F:"); Serial.print(stm_freq,1);
        Serial.print(" Hz  T:"); Serial.print(sim_tempC,1);
        Serial.print(" C  P:"); Serial.print(sim_bar,2);
        Serial.print(" bar  Q:"); Serial.print(sim_flowLpm,2);
        Serial.print(" L/min  R:"); Serial.println(stm_running);

        // Trame sensors → téléphone (T, P, Q)
        char telemSensors[64];
        snprintf(telemSensors, sizeof(telemSensors),
                 "TELEM | F:%.1f T:%.1f P:%.2f Q:%.2f\r\n",
                 stm_freq, sim_tempC, sim_bar, sim_flowLpm);
        bleSend(String(telemSensors));

        // FIX: trame fake STM32 → met à jour le gauge fréquence + état moteur
        char telemStm[80];
        snprintf(telemStm, sizeof(telemStm),
                 "TELEM F:%.1f A:%.2f Tf:%.1f R:%d T:0.0 P:0.00\r\n",
                 stm_freq, stm_freq / 50.0f, stm_target, stm_running);
        bleSend(String(telemStm));
    }

    /* ---- Lecture STM32 → BLE (si branché) ----------------------------- */
    while (STM32_Serial.available())
    {
        char c = (char)STM32_Serial.read();
        Serial.write(c);
        if (c == '\n')
        {
            if (stm_buf.length() > 0) { stm_buf += '\n'; bleSend(stm_buf); stm_buf = ""; }
        }
        else if (c != '\r') { stm_buf += c; if (stm_buf.length() >= 60) { bleSend(stm_buf); stm_buf = ""; } }
    }

    /* ---- Serial Monitor local → STM32 (debug) ------------------------- */
    if (Serial.available())
    {
        String line = Serial.readStringUntil('\n');
        line.trim();
        if (line.length() > 0) { Serial.print("[LOCAL] "); Serial.println(line); handle_ble_command(line); }
    }

    delay(1);
}
