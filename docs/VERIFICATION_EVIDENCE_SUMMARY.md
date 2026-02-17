## ✅ EVIDENCE-BASED RESOLUTION - COMPLETE

### What Was Added:

**New Columns:**
- `resolution_evidence` (JSONB) - Stores location, device_match, photo_reference, corrected_timestamp
- `evidence_status` - INSUFFICIENT, PARTIAL, COMPLETE
- `verified_by_role` - Role of person who resolved (supervisor, admin, etc.)

**Evidence Requirements by Trust Score:**

| Trust Score | Required | Optional |
|-------------|----------|----------|
| **50-100** | resolution_note only | - |
| **30-49** | resolution_note + at least 1 evidence | location, device_match, photo_reference |
| **0-29** | resolution_note + **photo_reference mandatory** | location, device_match |

**Special Rules:**
- `TIME_DRIFT` → Must provide `corrected_timestamp`
- `OFFLINE_EXCESS` → Supervisor remark minimum 15 characters

**New Functions:**

1. **`check_task_resolution_requirements(task_id)`**
   - Returns what evidence is required for specific task
   - Used by UI to show requirements before submission

2. **`validate_resolution_evidence(task_id, note, evidence)`**
   - Validates if provided evidence meets requirements
   - Returns detailed error if insufficient

3. **`resolve_verification_task()` - UPDATED**
   - Now requires `p_evidence` JSONB parameter
   - Validates evidence before allowing VERIFIED/JUSTIFIED
   - Rejects resolution if requirements not met
   - REJECTED action requires no evidence (just note)

**Evidence JSONB Structure:**
```json
{
  "location": "28.6139°N, 77.2090°E",
  "device_match": true,
  "photo_reference": "https://storage.url/photo.jpg",
  "corrected_timestamp": "2026-02-17T10:30:00Z",
  "supervisor_confirmation": "Confirmed with site manager"
}
```

**Example Validation:**
- Trust score = 25 → Requires photo_reference
- Supervisor tries to resolve with just note → **REJECTED**
- Supervisor provides photo → **ACCEPTED** (evidence_status: COMPLETE)

**Files:** `verification_evidence_enforcement.sql`, `VERIFICATION_EVIDENCE_SUMMARY.md`

**Key Benefit:** Supervisors cannot close low-trust tasks without providing adequate proof. Higher severity = more evidence required.
