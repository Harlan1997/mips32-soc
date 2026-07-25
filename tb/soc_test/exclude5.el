// Legacy SoC smoke coverage exclusions.
//
// This file intentionally has no active exclusions.
//
// Previous revisions listed reset-path FSM transitions such as
// REFILL_REQ->IDLE, ST_AR->ST_IDLE, and READ->IDLE. With the current RTL and
// VCS X-2025.06 FSM extraction, those transition objects are not present in the
// generated coverage database, so URG reported Warning-[UCAPI-EL-INVFSM] for
// every active rule. Keeping stale exclusions is misleading because they do not
// affect coverage and hide whether a future exclusion is valid.
//
// Add new exclusions only from a current full-exclusion dump and keep them tied
// to the current RTL hierarchy/FSM names.
