#include "diagnostics.h"

uint8_t diag_hid_itf_count = 0;
uint32_t diag_umounts = 0;
uint32_t diag_reports_in = 0;
uint32_t diag_ticks = 0;
uint32_t diag_max_tick_us = 0;

bool diag_downstream_tracking = false;
bool diag_watchdog_boot = false;
uint32_t diag_crash_code = 0;
uint32_t diag_fault_pc = 0;
uint8_t diag_crash_count = 0;
uint8_t diag_crash_flags = 0;
void (*diag_breadcrumb)(uint32_t) = nullptr;
bool diag_safe_mode = false;
bool need_to_reboot = false;
