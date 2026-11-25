/* =============================================================================

* VFD-Aquatec – STM32 – main.c

* =============================================================================

*

* MODES (sélectionnés via commande UART depuis ESP32 ou Serial direct) :

*

* MODE 1 – AUTO 50 Hz

* Le moteur démarre automatiquement à 50 Hz dès que l'ESP32 envoie

* la commande "MODE 1". Aucune intervention utilisateur requise.

*

* MODE 2 – MANUEL

* L'utilisateur envoie les commandes une à une :

* FREQ xx → fixer fréquence cible (5–50 Hz)

* START → démarrer rampe vers freq cible

* STOP → décélération puis arrêt

* STATUS → état courant

*

* MODE 3 – SÉQUENCE INTERACTIVE

* L'utilisateur construit sa séquence étape par étape puis lance GO :

* ADD <Hz> <sec> → ajouter une étape (ex: ADD 30 10)

* LIST → afficher la séquence en attente

* CLEAR → effacer toute la séquence

* GO → exécuter la séquence

* STOP → interrompre la séquence en cours

*

* CHANGEMENT DE MODE (depuis n'importe quel mode) :

* MODE 1 / MODE 2 / MODE 3

* → arrête proprement le moteur si nécessaire, puis active le nouveau mode.

* → Si une séquence MODE 3 est active, le changement attend la fin du

* step courant (flag pending_switch).

*

* TÉLÉMÉTRIE :

* TELEM ON → active envoi toutes les 500 ms

* TELEM OFF → désactive

* Format : "TELEM F:%.1f A:%.2f Tf:%.1f R:%d T:%.1f P:%.2f\r\n"

* (Température / Pression = 0.0 côté STM32, lues côté ESP32)

*

* ===========================================================================*/



#include "main.h"

#include <math.h>

#include <stdio.h>

#include <string.h>

#include <stdlib.h>



/* -------------------------------------------------------------------------- */

/* Handles HAL */

/* -------------------------------------------------------------------------- */

ADC_HandleTypeDef hadc3;

TIM_HandleTypeDef htim1;

UART_HandleTypeDef huart4;

I2C_HandleTypeDef hi2c1;



/* -------------------------------------------------------------------------- */

/* Constantes SPWM */

/* -------------------------------------------------------------------------- */

#define TABLE_SIZE 360

#define PWM_PERIOD 8500



/* -------------------------------------------------------------------------- */

/* Table sinus + variables SPWM */

/* -------------------------------------------------------------------------- */

float sine_table[TABLE_SIZE];



volatile float phase = 0.0f;

volatile float phase_increment = 0.0f;

volatile float frequency = 1.0f; /* fréquence réelle courante (Hz) */

volatile float amplitude = 0.1f; /* amplitude V/F courante */



/* -------------------------------------------------------------------------- */

/* Contrôle moteur */

/* -------------------------------------------------------------------------- */

volatile float target_frequency = 0.0f;

volatile uint8_t motor_running = 0;



/* Rampe non-bloquante */

volatile uint8_t ramp_active = 0;

volatile uint8_t ramp_direction = 0; /* 1 = montée, 0 = descente */

uint32_t last_ramp_tick = 0;



/* -------------------------------------------------------------------------- */

/* Flags commandes (posés dans la réception UART, traités dans main loop) */

/* -------------------------------------------------------------------------- */

volatile uint8_t cmd_start = 0;

volatile uint8_t cmd_stop = 0;

volatile uint8_t cmd_freq = 0;

volatile float cmd_new_freq = 0.0f;



/* -------------------------------------------------------------------------- */

/* MODES */

/* -------------------------------------------------------------------------- */

#define MODE_NONE 0

#define MODE_AUTO 1

#define MODE_MANUAL 2

#define MODE_SEQ 3



volatile uint8_t current_mode = MODE_NONE;

volatile uint8_t pending_switch = 0; /* changement de mode en attente */

volatile uint8_t pending_mode = MODE_NONE;



/* -------------------------------------------------------------------------- */

/* Séquence interactive (MODE 3) */

/* -------------------------------------------------------------------------- */

#define SEQ_MAX_STEPS 50



typedef struct {

float freq_hz;

uint32_t duration_ms;

} SeqStep_t;



SeqStep_t seq_steps[SEQ_MAX_STEPS];

uint8_t seq_count = 0;

uint8_t seq_running = 0;

uint8_t seq_current_step = 0;

uint32_t seq_step_start = 0; /* tick de début du step courant */

uint8_t seq_step_phase = 0; /* 0 = rampe vers freq, 1 = attente durée */



/* -------------------------------------------------------------------------- */

/* UART */

/* -------------------------------------------------------------------------- */

char tx_buf[128];



/* -------------------------------------------------------------------------- */

/* Télémétrie */

/* -------------------------------------------------------------------------- */

volatile uint8_t telem_active = 0;

uint32_t last_telem = 0;



/* -------------------------------------------------------------------------- */

/* Prototypes */

/* -------------------------------------------------------------------------- */

void SystemClock_Config(void);

static void MX_GPIO_Init(void);

static void MX_ADC3_Init(void);

static void MX_TIM1_Init(void);

static void MX_UART4_Init(void);



void Generate_Sine_Table(void);

void Start_PWM(void);



void motor_start(void);

void motor_stop(void);

void set_frequency(float freq);

void print_status(void);



static void Ramp_Step(void);

static void Send(const char *s);

static void SendBuf(void);



void handle_command(char *cmd);

void activate_mode(uint8_t mode);

void do_switch_mode(uint8_t mode);



void seq_print_list(void);

void seq_run_tick(void);



/* ========================================================================== */

/* Utilitaires UART */

/* ========================================================================== */

static void Send(const char *s)

{

HAL_UART_Transmit(&huart4, (uint8_t *)s, strlen(s), 1000);

}



static void SendBuf(void)

{

HAL_UART_Transmit(&huart4, (uint8_t *)tx_buf, strlen(tx_buf), 1000);

}



/* ========================================================================== */

/* Table sinus */

/* ========================================================================== */

void Generate_Sine_Table(void)

{

for (int i = 0; i < TABLE_SIZE; i++)

{

float angle = (2.0f * 3.1415926f * i) / TABLE_SIZE;

sine_table[i] = sinf(angle);

}

}



/* ========================================================================== */

/* Démarrage PWM */

/* ========================================================================== */

void Start_PWM(void)

{

HAL_TIM_PWM_Start(&htim1, TIM_CHANNEL_1);

HAL_TIM_PWM_Start(&htim1, TIM_CHANNEL_2);

HAL_TIM_PWM_Start(&htim1, TIM_CHANNEL_3);

HAL_TIMEx_PWMN_Start(&htim1, TIM_CHANNEL_1);

HAL_TIMEx_PWMN_Start(&htim1, TIM_CHANNEL_2);

HAL_TIMEx_PWMN_Start(&htim1, TIM_CHANNEL_3);

__HAL_TIM_ENABLE_IT(&htim1, TIM_IT_UPDATE);

}



/* ========================================================================== */

/* ISR TIM1 – calcul SPWM */

/* ========================================================================== */

void HAL_TIM_PeriodElapsedCallback(TIM_HandleTypeDef *htim)

{

if (htim->Instance == TIM1)

{

/* RepetitionCounter=1 + center-aligned → ISR à 5 kHz */

float f_pwm = 10000.0f;



phase_increment = (frequency * TABLE_SIZE) / f_pwm;

phase += phase_increment;

if (phase >= TABLE_SIZE) phase -= TABLE_SIZE;



int idxA = (int)phase;

int idxB = (idxA + 120) % TABLE_SIZE;

int idxC = (idxA + 240) % TABLE_SIZE;



float sinA = sine_table[idxA];

float sinB = sine_table[idxB];

float sinC = sine_table[idxC];



uint16_t dutyA = (uint16_t)((sinA * amplitude + 1.0f) * (PWM_PERIOD / 2));

uint16_t dutyB = (uint16_t)((sinB * amplitude + 1.0f) * (PWM_PERIOD / 2));

uint16_t dutyC = (uint16_t)((sinC * amplitude + 1.0f) * (PWM_PERIOD / 2));



__HAL_TIM_SET_COMPARE(&htim1, TIM_CHANNEL_1, dutyA);

__HAL_TIM_SET_COMPARE(&htim1, TIM_CHANNEL_2, dutyB);

__HAL_TIM_SET_COMPARE(&htim1, TIM_CHANNEL_3, dutyC);





}

}



/* ========================================================================== */

/* Rampe non-bloquante (1 pas toutes les 10 ms depuis main loop) */

/* ========================================================================== */

static void Ramp_Step(void)

{

float K = 1.0f / 50.0f;

float V_boost = 0.15f; /* 0.05 bus 325 V | 0.15 pour tests 80 V */



if (ramp_direction == 1) /* ---- MONTÉE --------------------------------- */

{

if (frequency < target_frequency)

{

if (frequency < 5.0f)

{

frequency += 0.01f;

amplitude = K * frequency + V_boost;

}

else

{

frequency += 0.05f;

amplitude = K * frequency;

}

if (frequency > target_frequency) frequency = target_frequency;

if (amplitude > 1.0f) amplitude = 1.0f;

}

else

{

ramp_active = 0;

sprintf(tx_buf, "[OK] Moteur tourne a %.1f Hz\r\n", frequency);

SendBuf();

}

}

else /* ---- DESCENTE --------------------------------------------------- */

{

if (frequency > target_frequency)

{

frequency -= 0.05f;

if (frequency < target_frequency) frequency = target_frequency;

amplitude = K * frequency;

if (amplitude < 0.02f) amplitude = 0.02f;

}

else

{

if (target_frequency <= 1.0f)

{

/* Arrêt complet */

ramp_active = 0;

frequency = 1.0f;

amplitude = 0.1f;

motor_running = 0;

Send("[OK] Moteur ARRETE\r\n");



/* Changement de mode en attente ? */

if (pending_switch)

{

pending_switch = 0;

activate_mode(pending_mode);

}

}

else

{

/* Décélération vers nouvelle fréquence cible */

ramp_active = 0;

sprintf(tx_buf, "[OK] Moteur tourne a %.1f Hz\r\n", frequency);

SendBuf();

}

}

}

}



/* ========================================================================== */

/* Contrôle moteur */

/* ========================================================================== */

void motor_start(void)

{

if (motor_running)

{

Send("[WARN] Moteur deja en marche\r\n");

return;

}

if (target_frequency < 5.0f)

{

Send("[ERR] Tape FREQ xx d abord (min 5 Hz)\r\n");

return;

}

motor_running = 1;

ramp_active = 1;

ramp_direction = 1;

last_ramp_tick = HAL_GetTick();

sprintf(tx_buf, "[OK] Demarrage rampe vers %.1f Hz...\r\n", target_frequency);

SendBuf();

}



void motor_stop(void)

{

if (!motor_running)

{

Send("[WARN] Moteur deja arrete\r\n");

return;

}

/* Annule la séquence en cours si nécessaire */

seq_running = 0;



target_frequency = 0.0f;

ramp_active = 1;

ramp_direction = 0;

last_ramp_tick = HAL_GetTick();

Send("[OK] Deceleration...\r\n");

}



void set_frequency(float freq)

{

if (freq < 5.0f || freq > 50.0f)

{

Send("[ERR] Frequence hors limites (5–50 Hz)\r\n");

return;

}

target_frequency = freq;

sprintf(tx_buf, "[OK] Freq cible = %.1f Hz\r\n", target_frequency);

SendBuf();



if (motor_running)

{

ramp_active = 1;

ramp_direction = (frequency < target_frequency) ? 1 : 0;

last_ramp_tick = HAL_GetTick();

}

}



void print_status(void)

{

const char *mode_str = (current_mode == MODE_AUTO) ? "AUTO" :

(current_mode == MODE_MANUAL) ? "MANUEL" :

(current_mode == MODE_SEQ) ? "SEQUENCE" : "AUCUN";



Send("-----------------------------\r\n");

sprintf(tx_buf, "Mode : %s\r\n", mode_str); SendBuf();

sprintf(tx_buf, "Moteur : %s\r\n",

motor_running ? "EN MARCHE" : "ARRETE"); SendBuf();

sprintf(tx_buf, "Freq cible : %.1f Hz\r\n", target_frequency); SendBuf();

sprintf(tx_buf, "Freq reelle: %.1f Hz\r\n", frequency); SendBuf();

sprintf(tx_buf, "Amplitude : %.3f\r\n", amplitude); SendBuf();

if (current_mode == MODE_SEQ)

{

sprintf(tx_buf, "Seq steps : %d running=%d step=%d\r\n",

seq_count, seq_running, seq_current_step); SendBuf();

}

Send("-----------------------------\r\n");

}



/* ========================================================================== */

/* Séquence (MODE 3) */

/* ========================================================================== */

void seq_print_list(void)

{

if (seq_count == 0)

{

Send("[SEQ] Aucune etape enregistree\r\n");

return;

}

Send("[SEQ] Liste des etapes :\r\n");

for (uint8_t i = 0; i < seq_count; i++)

{

sprintf(tx_buf, " [%d] %.1f Hz pendant %lu s\r\n",

i + 1,

seq_steps[i].freq_hz,

(unsigned long)(seq_steps[i].duration_ms / 1000));

SendBuf();

}

}



/* Tick de la séquence – appelé depuis main loop */

void seq_run_tick(void)

{

if (!seq_running || seq_current_step >= seq_count) return;



uint32_t now = HAL_GetTick();



if (seq_step_phase == 0)

{

/* Phase 0 : lancer la rampe vers la fréquence du step */

float target = seq_steps[seq_current_step].freq_hz;

set_frequency(target);

if (!motor_running) motor_start();

seq_step_phase = 1;

seq_step_start = now; /* le chrono démarre MAINTENANT */

}

else

{

/* Phase 1 : attendre que la rampe soit stable ET que la durée

* soit écoulée. On laisse ramp_active se terminer seul. */

if (!ramp_active)

{

/* Rampe terminée → on attend la durée définie */

uint32_t elapsed = now - seq_step_start;

if (elapsed >= seq_steps[seq_current_step].duration_ms)

{

/* Step suivant */

seq_current_step++;



if (seq_current_step >= seq_count)

{

/* Séquence terminée */

seq_running = 0;

Send("[SEQ] Sequence terminee. Arret moteur...\r\n");



/* Changement de mode en attente ? */

if (pending_switch)

{

pending_switch = 0;

uint8_t m = pending_mode;

motor_stop(); /* arrêt puis do_switch */

/* do_switch sera appelé depuis Ramp_Step arrêt */

pending_switch = 1;

pending_mode = m;

}

else

{

motor_stop();

}

}

else

{

seq_step_phase = 0; /* prépare le prochain step */

sprintf(tx_buf, "[SEQ] Step %d/%d : %.1f Hz pendant %lu s\r\n",

seq_current_step + 1, seq_count,

seq_steps[seq_current_step].freq_hz,

(unsigned long)(seq_steps[seq_current_step].duration_ms / 1000));

SendBuf();

}

}

}

}

}



/* ========================================================================== */

/* Gestion des modes */

/* ========================================================================== */



/* Active un mode (moteur déjà à l'arrêt quand cette fonction est appelée) */

void activate_mode(uint8_t mode)

{

current_mode = mode;



if (mode == MODE_AUTO)

{

Send("[MODE 1] AUTO – Demarrage 50 Hz\r\n");

target_frequency = 50.0f;

motor_start();

}

else if (mode == MODE_MANUAL)

{

Send("[MODE 2] MANUEL – en attente de commandes\r\n");

Send(" FREQ xx | START | STOP | STATUS\r\n");

}

else if (mode == MODE_SEQ)

{

Send("[MODE 3] SEQUENCE – construis ta sequence :\r\n");

Send(" ADD <Hz> <sec> LIST CLEAR GO STOP\r\n");

}

}



/* Demande un changement de mode ; gère l'arrêt propre si nécessaire */

void do_switch_mode(uint8_t mode)

{

if (mode == current_mode)

{

sprintf(tx_buf, "[WARN] Deja en MODE %d\r\n", mode);

SendBuf();

return;

}



if (motor_running)

{

sprintf(tx_buf, "[MODE] Changement vers MODE %d apres arret...\r\n", mode);

SendBuf();

pending_switch = 1;

pending_mode = mode;



/* Si séquence active, on attend la fin du step avant de stopper */

if (seq_running)

{

/* pending_switch sera traité dans seq_run_tick step suivant */

}

else

{

motor_stop(); /* arrêt → Ramp_Step appellera activate_mode */

}

}

else

{

/* Moteur déjà arrêté : basculement immédiat */

activate_mode(mode);

}

}



/* ========================================================================== */

/* Interpréteur de commandes */

/* ========================================================================== */

void handle_command(char *cmd)

{

/* Echo debug */

sprintf(tx_buf, "[RECU] %s\r\n", cmd);

SendBuf();



/* ---- Changement de mode -------------------------------------------- */

if (strcmp(cmd, "MODE 1") == 0) { do_switch_mode(MODE_AUTO); return; }

if (strcmp(cmd, "MODE 2") == 0) { do_switch_mode(MODE_MANUAL); return; }

if (strcmp(cmd, "MODE 3") == 0) { do_switch_mode(MODE_SEQ); return; }



/* ---- Commandes universelles ----------------------------------------- */

if (strcmp(cmd, "STATUS") == 0) { print_status(); return; }



if (strcmp(cmd, "TELEM ON") == 0)

{

telem_active = 1;

Send("[OK] Telemetrie ON\r\n");

return;

}

if (strcmp(cmd, "TELEM OFF") == 0)

{

telem_active = 0;

Send("[OK] Telemetrie OFF\r\n");

return;

}



/* ---- MODE 2 : commandes manuelles ----------------------------------- */

if (current_mode == MODE_MANUAL || current_mode == MODE_NONE)

{

if (strncmp(cmd, "FREQ ", 5) == 0)

{

float f = atof(cmd + 5);

set_frequency(f);

return;

}

if (strcmp(cmd, "START") == 0) { motor_start(); return; }

if (strcmp(cmd, "STOP") == 0) { motor_stop(); return; }

}



/* ---- MODE 3 : commandes séquence ------------------------------------ */

if (current_mode == MODE_SEQ)

{

if (strncmp(cmd, "ADD ", 4) == 0)

{

if (seq_running)

{

Send("[ERR] Sequence en cours. STOP d abord.\r\n");

return;

}

if (seq_count >= SEQ_MAX_STEPS)

{

Send("[ERR] Sequence pleine (50 steps max)\r\n");

return;

}

/* Parsing : ADD <Hz> <sec> */

char *p1 = cmd + 4;

char *p2 = strchr(p1, ' ');

if (p2 == NULL)

{

Send("[ERR] Usage : ADD <Hz> <sec>\r\n");

return;

}

*p2 = '\0';

float hz = atof(p1);

uint32_t sec = (uint32_t)atoi(p2 + 1);

*p2 = ' '; /* restaurer pour ne pas corrompre cmd */



if (hz < 5.0f || hz > 50.0f)

{

Send("[ERR] Frequence hors limites (5–50 Hz)\r\n");

return;

}

if (sec == 0)

{

Send("[ERR] Duree doit etre >= 1 sec\r\n");

return;

}

seq_steps[seq_count].freq_hz = hz;

seq_steps[seq_count].duration_ms = sec * 1000UL;

seq_count++;

sprintf(tx_buf, "[SEQ] Step %d ajoute : %.1f Hz / %lu s\r\n",

seq_count, hz, (unsigned long)sec);

SendBuf();

return;

}



if (strcmp(cmd, "LIST") == 0) { seq_print_list(); return; }



if (strcmp(cmd, "CLEAR") == 0)

{

if (seq_running)

{

Send("[ERR] Sequence en cours. STOP d abord.\r\n");

return;

}

seq_count = 0;

Send("[SEQ] Sequence effacee.\r\n");

return;

}



if (strcmp(cmd, "GO") == 0)

{

if (seq_running)

{

Send("[WARN] Sequence deja en cours.\r\n");

return;

}

if (seq_count == 0)

{

Send("[ERR] Aucune etape. Utilise ADD <Hz> <sec>\r\n");

return;

}

seq_current_step = 0;

seq_step_phase = 0;

seq_running = 1;

sprintf(tx_buf, "[SEQ] GO – %d etapes\r\n", seq_count);

SendBuf();

sprintf(tx_buf, "[SEQ] Step 1/%d : %.1f Hz pendant %lu s\r\n",

seq_count,

seq_steps[0].freq_hz,

(unsigned long)(seq_steps[0].duration_ms / 1000));

SendBuf();

return;

}



if (strcmp(cmd, "STOP") == 0)

{

seq_running = 0;

motor_stop();

return;

}

}



/* ---- MODE 1 : commandes ignorées sauf STOP/STATUS ------------------- */

if (current_mode == MODE_AUTO)

{

if (strcmp(cmd, "STOP") == 0) { motor_stop(); return; }

Send("[WARN] MODE 1 AUTO – seul STOP est accepte (ou MODE 2 / MODE 3)\r\n");

return;

}



Send("[ERR] Commande inconnue\r\n");

}



/* ========================================================================== */

/* Main */

/* ========================================================================== */

int main(void)

{

HAL_Init();

SystemClock_Config();

MX_GPIO_Init();

MX_ADC3_Init();

MX_TIM1_Init();

MX_UART4_Init();



Generate_Sine_Table();

Start_PWM();



/* Message de bienvenue + menu */

Send("\r\n===============================\r\n");

Send(" VFD-Aquatec – STM32G474\r\n");

Send("===============================\r\n");

Send(" MODE 1 -> Auto 50 Hz\r\n");

Send(" MODE 2 -> Manuel\r\n");

Send(" MODE 3 -> Sequence interactive\r\n");

Send(" STATUS -> Etat courant\r\n");

Send(" TELEM ON/OFF -> Telemetrie\r\n");

Send("-------------------------------\r\n");

Send("Tape MODE 1 / MODE 2 / MODE 3\r\n");

Send("> ");



uint8_t rx_byte;

static char cmd_buf[64];

static int idx = 0;



while (1)

{

/* ---- Réception UART caractère par caractère -------------------- */

if (HAL_UART_Receive(&huart4, &rx_byte, 1, 5) == HAL_OK)

{

if (rx_byte == '\r' || rx_byte == '\n')

{

if (idx > 0)

{

cmd_buf[idx] = '\0';

idx = 0;

handle_command(cmd_buf);

Send("> ");

}

}

else if (idx < 63)

{

cmd_buf[idx++] = rx_byte;

}

}



/* ---- Rampe non-bloquante --------------------------------------- */

if (ramp_active)

{

uint32_t now = HAL_GetTick();

if (now - last_ramp_tick >= 10)

{

last_ramp_tick = now;

Ramp_Step();

}

}



/* ---- Tick séquence (MODE 3) ------------------------------------ */

if (current_mode == MODE_SEQ && seq_running)

{

seq_run_tick();

}



/* ---- Télémétrie 500 ms ---------------------------------------- */

if (telem_active)

{

uint32_t now = HAL_GetTick();

if (now - last_telem >= 500)

{

last_telem = now;

/* T et P lues côté ESP32 ; STM32 envoie 0.0 pour ces deux */

sprintf(tx_buf,

"TELEM F:%.1f A:%.2f Tf:%.1f R:%d T:0.0 P:0.00\r\n",

frequency, amplitude, target_frequency,

motor_running);

SendBuf();

}

}

}

}



/* ========================================================================== */

/* Initialisations HAL (inchangées par rapport à ta version validée) */

/* ========================================================================== */

void SystemClock_Config(void)

{

RCC_OscInitTypeDef RCC_OscInitStruct = {0};

RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

HAL_PWREx_ControlVoltageScaling(PWR_REGULATOR_VOLTAGE_SCALE1_BOOST);

RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSE;

RCC_OscInitStruct.HSEState = RCC_HSE_ON;

RCC_OscInitStruct.PLL.PLLState = RCC_PLL_ON;

RCC_OscInitStruct.PLL.PLLSource = RCC_PLLSOURCE_HSE;

RCC_OscInitStruct.PLL.PLLM = RCC_PLLM_DIV2;

RCC_OscInitStruct.PLL.PLLN = 85;

RCC_OscInitStruct.PLL.PLLP = RCC_PLLP_DIV2;

RCC_OscInitStruct.PLL.PLLQ = RCC_PLLQ_DIV2;

RCC_OscInitStruct.PLL.PLLR = RCC_PLLR_DIV2;

if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK) Error_Handler();

RCC_ClkInitStruct.ClockType = RCC_CLOCKTYPE_HCLK | RCC_CLOCKTYPE_SYSCLK

| RCC_CLOCKTYPE_PCLK1 | RCC_CLOCKTYPE_PCLK2;

RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_PLLCLK;

RCC_ClkInitStruct.AHBCLKDivider = RCC_SYSCLK_DIV1;

RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV1;

RCC_ClkInitStruct.APB2CLKDivider = RCC_HCLK_DIV1;

if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_4) != HAL_OK) Error_Handler();

}



static void MX_ADC3_Init(void)

{

ADC_MultiModeTypeDef multimode = {0};

ADC_ChannelConfTypeDef sConfig = {0};

hadc3.Instance = ADC3;

hadc3.Init.ClockPrescaler = ADC_CLOCK_SYNC_PCLK_DIV4;

hadc3.Init.Resolution = ADC_RESOLUTION_12B;

hadc3.Init.DataAlign = ADC_DATAALIGN_RIGHT;

hadc3.Init.GainCompensation = 0;

hadc3.Init.ScanConvMode = ADC_SCAN_DISABLE;

hadc3.Init.EOCSelection = ADC_EOC_SINGLE_CONV;

hadc3.Init.LowPowerAutoWait = DISABLE;

hadc3.Init.ContinuousConvMode = DISABLE;

hadc3.Init.NbrOfConversion = 1;

hadc3.Init.DiscontinuousConvMode = DISABLE;

hadc3.Init.ExternalTrigConv = ADC_SOFTWARE_START;

hadc3.Init.ExternalTrigConvEdge = ADC_EXTERNALTRIGCONVEDGE_NONE;

hadc3.Init.DMAContinuousRequests = DISABLE;

hadc3.Init.Overrun = ADC_OVR_DATA_PRESERVED;

hadc3.Init.OversamplingMode = DISABLE;

if (HAL_ADC_Init(&hadc3) != HAL_OK) Error_Handler();

multimode.Mode = ADC_MODE_INDEPENDENT;

if (HAL_ADCEx_MultiModeConfigChannel(&hadc3, &multimode) != HAL_OK) Error_Handler();

sConfig.Channel = ADC_CHANNEL_1;

sConfig.Rank = ADC_REGULAR_RANK_1;

sConfig.SamplingTime = ADC_SAMPLETIME_2CYCLES_5;

sConfig.SingleDiff = ADC_SINGLE_ENDED;

sConfig.OffsetNumber = ADC_OFFSET_NONE;

sConfig.Offset = 0;

if (HAL_ADC_ConfigChannel(&hadc3, &sConfig) != HAL_OK) Error_Handler();

}



static void MX_TIM1_Init(void)

{

TIM_MasterConfigTypeDef sMasterConfig = {0};

TIM_OC_InitTypeDef sConfigOC = {0};

TIM_BreakDeadTimeConfigTypeDef sBreakDeadTimeConfig = {0};

htim1.Instance = TIM1;

htim1.Init.Prescaler = 0;

htim1.Init.CounterMode = TIM_COUNTERMODE_CENTERALIGNED1;

htim1.Init.Period = 8500;

htim1.Init.ClockDivision = TIM_CLOCKDIVISION_DIV1;

htim1.Init.RepetitionCounter = 1;

htim1.Init.AutoReloadPreload = TIM_AUTORELOAD_PRELOAD_DISABLE;

if (HAL_TIM_PWM_Init(&htim1) != HAL_OK) Error_Handler();

sMasterConfig.MasterOutputTrigger = TIM_TRGO_RESET;

sMasterConfig.MasterOutputTrigger2 = TIM_TRGO2_RESET;

sMasterConfig.MasterSlaveMode = TIM_MASTERSLAVEMODE_DISABLE;

if (HAL_TIMEx_MasterConfigSynchronization(&htim1, &sMasterConfig) != HAL_OK) Error_Handler();

sConfigOC.OCMode = TIM_OCMODE_PWM1;

sConfigOC.Pulse = 4250;

sConfigOC.OCPolarity = TIM_OCPOLARITY_HIGH;

sConfigOC.OCNPolarity = TIM_OCNPOLARITY_HIGH;

sConfigOC.OCFastMode = TIM_OCFAST_DISABLE;

sConfigOC.OCIdleState = TIM_OCIDLESTATE_RESET;

sConfigOC.OCNIdleState = TIM_OCNIDLESTATE_RESET;

if (HAL_TIM_PWM_ConfigChannel(&htim1, &sConfigOC, TIM_CHANNEL_1) != HAL_OK) Error_Handler();

if (HAL_TIM_PWM_ConfigChannel(&htim1, &sConfigOC, TIM_CHANNEL_2) != HAL_OK) Error_Handler();

if (HAL_TIM_PWM_ConfigChannel(&htim1, &sConfigOC, TIM_CHANNEL_3) != HAL_OK) Error_Handler();

sBreakDeadTimeConfig.OffStateRunMode = TIM_OSSR_DISABLE;

sBreakDeadTimeConfig.OffStateIDLEMode = TIM_OSSI_DISABLE;

sBreakDeadTimeConfig.LockLevel = TIM_LOCKLEVEL_OFF;

sBreakDeadTimeConfig.DeadTime = 250;

sBreakDeadTimeConfig.BreakState = TIM_BREAK_DISABLE;

sBreakDeadTimeConfig.BreakPolarity = TIM_BREAKPOLARITY_LOW;

sBreakDeadTimeConfig.BreakFilter = 0;

sBreakDeadTimeConfig.BreakAFMode = TIM_BREAK_AFMODE_INPUT;

sBreakDeadTimeConfig.Break2State = TIM_BREAK2_DISABLE;

sBreakDeadTimeConfig.Break2Polarity = TIM_BREAK2POLARITY_LOW;

sBreakDeadTimeConfig.Break2Filter = 0;

sBreakDeadTimeConfig.Break2AFMode = TIM_BREAK_AFMODE_INPUT;

sBreakDeadTimeConfig.AutomaticOutput = TIM_AUTOMATICOUTPUT_DISABLE;

if (HAL_TIMEx_ConfigBreakDeadTime(&htim1, &sBreakDeadTimeConfig) != HAL_OK) Error_Handler();

HAL_NVIC_SetPriority(TIM1_UP_TIM16_IRQn, 0, 0);

HAL_NVIC_EnableIRQ(TIM1_UP_TIM16_IRQn);

HAL_TIM_MspPostInit(&htim1);

}



static void MX_UART4_Init(void)

{

huart4.Instance = UART4;

huart4.Init.BaudRate = 115200;

huart4.Init.WordLength = UART_WORDLENGTH_8B;

huart4.Init.StopBits = UART_STOPBITS_1;

huart4.Init.Parity = UART_PARITY_NONE;

huart4.Init.Mode = UART_MODE_TX_RX;

huart4.Init.HwFlowCtl = UART_HWCONTROL_NONE;

huart4.Init.OverSampling = UART_OVERSAMPLING_16;

huart4.Init.OneBitSampling = UART_ONE_BIT_SAMPLE_DISABLE;

huart4.Init.ClockPrescaler = UART_PRESCALER_DIV1;

huart4.AdvancedInit.AdvFeatureInit = UART_ADVFEATURE_NO_INIT;

if (HAL_UART_Init(&huart4) != HAL_OK) Error_Handler();

if (HAL_UARTEx_SetTxFifoThreshold(&huart4, UART_TXFIFO_THRESHOLD_1_8) != HAL_OK) Error_Handler();

if (HAL_UARTEx_SetRxFifoThreshold(&huart4, UART_RXFIFO_THRESHOLD_1_8) != HAL_OK) Error_Handler();

if (HAL_UARTEx_DisableFifoMode(&huart4) != HAL_OK) Error_Handler();

}



static void MX_GPIO_Init(void)

{

GPIO_InitTypeDef GPIO_InitStruct = {0};

__HAL_RCC_GPIOC_CLK_ENABLE();

__HAL_RCC_GPIOF_CLK_ENABLE();

__HAL_RCC_GPIOB_CLK_ENABLE();

__HAL_RCC_GPIOA_CLK_ENABLE();

HAL_GPIO_WritePin(GPIOA, GPIO_PIN_12, GPIO_PIN_RESET);

GPIO_InitStruct.Pin = GPIO_PIN_10 | GPIO_PIN_11;

GPIO_InitStruct.Mode = GPIO_MODE_INPUT;

GPIO_InitStruct.Pull = GPIO_NOPULL;

HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);

GPIO_InitStruct.Pin = GPIO_PIN_12;

GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;

GPIO_InitStruct.Pull = GPIO_NOPULL;

GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;

HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);

}



void Error_Handler(void)

{

__disable_irq();

while (1) {}

}



#ifdef USE_FULL_ASSERT

void assert_failed(uint8_t *file, uint32_t line) {}

#endif
