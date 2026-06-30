MODULE "dcache"
FSM "state" {
  TRANSITION "REFILL_REQ" -> "IDLE" "reset";
}
