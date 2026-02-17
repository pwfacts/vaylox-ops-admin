## ✅ PHOTO AUTHENTICITY VALIDATION - COMPLETE

### What Was Added:

**New Table:** `evidence_media_metadata`
- Stores photo metadata and validation results
- Tracks captured_at, captured_lat/lng, device_fingerprint, file_hash
- Records validity_status: VALID, SUSPICIOUS, INVALID
- Stores detailed validation results for each check

**Four Validation Checks:**

1. **Time Check**
   - Photo captured_at must be within shift window ± 90 minutes
   - Example: Morning shift 08:00-16:00 → Valid 06:30-17:30
   - Flag if violated: `TIME_OUT_OF_RANGE` → INVALID

2. **Location Check**
   - Distance from photo GPS to unit location < unit_radius
   - Uses Haversine formula for accurate distance
   - Flag if violated: `LOCATION_OUT_OF_RANGE` → SUSPICIOUS

3. **Device Check**
   - device_fingerprint must exist in workforce_trusted_devices
   - Ensures photo from guard's trusted device
   - Flag if violated: `UNTRUSTED_DEVICE` → SUSPICIOUS

4. **Reuse Check**
   - file_hash cannot exist in previous attendance
   - Prevents reusing old photos
   - Flag if violated: `PHOTO_REUSED` → INVALID

**Decision Types:**

| Photo Status | Decision | Required |
|--------------|----------|----------|
| VALID | AUTOMATIC | Normal resolution |
| SUSPICIOUS | AUTOMATIC | Normal resolution (warnings logged) |
| INVALID | MANUAL_OVERRIDE | override_reason (min 20 chars) |

**Updated `resolve_verification_task()`:**
- New param: `p_photo_metadata` (JSONB)
- New param: `p_override_reason` (TEXT)
- Validates photo if provided
- If INVALID → Requires override_reason 20+ chars
- If override missing → Returns error
- If override provided → Resolution allowed (logged as MANUAL_OVERRIDE)

**Photo Metadata Format:**
```json
{
  "captured_at": "2026-02-17T10:30:00Z",
  "captured_lat": 28.6139,
  "captured_lng": 77.2090,
  "device_fingerprint": "device-uuid",
  "file_hash": "sha256-hash"
}
```

**Validation Result Example:**
```json
{
  "validity_status": "INVALID",
  "validation_flags": ["TIME_OUT_OF_RANGE", "PHOTO_REUSED"],
  "time_valid": false,
  "location_valid": true,
  "device_valid": true,
  "reuse_valid": false,
  "requires_override": true
}
```

**New Functions:**
- `validate_photo_authenticity(task_id, photo_metadata)` - Run validation
- `get_photo_validation_status(task_id)` - Get validation results

**Key Benefit:** 
- Evidence must be tied to real shift presence
- Cannot upload random/old photos
- Supervisor can override with justification
- All overrides logged for audit

**Files:** `evidence_authenticity_validation.sql`, `PHOTO_AUTHENTICITY_SUMMARY.md`
