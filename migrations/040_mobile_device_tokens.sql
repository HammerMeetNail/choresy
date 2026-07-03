-- APNs device tokens for the native iOS app (iOS v1 plan P1/A3).
-- One row per device token; a token is globally unique to a physical device,
-- so re-registration by a different account takes the token over (the device
-- changed hands / logged into another account).
CREATE TABLE IF NOT EXISTS mobile_device_tokens (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token TEXT NOT NULL UNIQUE,
    environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
    bundle_id TEXT NOT NULL,
    device_name TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mobile_device_tokens_user ON mobile_device_tokens(user_id);
