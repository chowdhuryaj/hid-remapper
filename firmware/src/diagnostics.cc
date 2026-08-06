#include "diagnostics.h"

uint8_t diag_hid_itf_count = 0;
uint32_t diag_umounts = 0;
uint32_t diag_reports_in = 0;
uint32_t diag_ticks = 0;
uint32_t diag_max_tick_us = 0;

bool diag_downstream_tracking = false;
bool diag_safe_mode = false;
bool need_to_reboot = false;
