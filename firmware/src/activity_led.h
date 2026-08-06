#ifndef _ACTIVITY_LED_H_
#define _ACTIVITY_LED_H_

void activity_led_on();
void activity_led_off_maybe();

// Fork addition: one call per main-loop iteration instead of
// activity_led_off_maybe(). Patterns, in priority order:
//   safe mode        - fast blink (100 ms on / 100 ms off)
//   no downstream    - slow blink (100 ms on / 900 ms off)
//   normal           - upstream behavior (50 ms flash per report)
// "no downstream" only ever shows on builds that track it
// (diag_downstream_tracking), so dual/serial variants are unchanged.
void activity_led_task();

#endif
