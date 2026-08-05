-- Additive provider-neutral account and Web session foundation.
-- No existing ownership data is migrated or backfilled by this change.

BEGIN;

CREATE TABLE "Account" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "status" TEXT NOT NULL DEFAULT 'active',
  "version" INTEGER NOT NULL DEFAULT 1,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  "disabledAt" TIMESTAMP(3),
  "deletionRequestedAt" TIMESTAMP(3),

  CONSTRAINT "Account_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "Account_status_check"
    CHECK ("status" IN ('active', 'locked', 'deletion_pending', 'deleted')),
  CONSTRAINT "Account_version_positive_check" CHECK ("version" > 0)
);

CREATE TABLE "AuthIdentity" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "accountId" UUID NOT NULL,
  "provider" TEXT NOT NULL,
  "providerSubject" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "lastUsedAt" TIMESTAMP(3),
  "disabledAt" TIMESTAMP(3),

  CONSTRAINT "AuthIdentity_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "AuthIdentity_provider_nonempty_check"
    CHECK (char_length("provider") BETWEEN 1 AND 64),
  CONSTRAINT "AuthIdentity_providerSubject_nonempty_check"
    CHECK (char_length("providerSubject") BETWEEN 1 AND 512)
);

CREATE TABLE "WebSession" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "accountId" UUID NOT NULL,
  "tokenHash" CHAR(64) NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "lastSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "revokedAt" TIMESTAMP(3),
  "rotationCounter" INTEGER NOT NULL DEFAULT 0,
  "version" INTEGER NOT NULL DEFAULT 1,
  "accountVersion" INTEGER NOT NULL,
  "deviceLabel" VARCHAR(80) NOT NULL DEFAULT '',
  "platform" VARCHAR(32) NOT NULL DEFAULT 'unknown',
  "replacedBySessionId" UUID,

  CONSTRAINT "WebSession_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "WebSession_tokenHash_format_check"
    CHECK ("tokenHash" ~ '^[0-9a-f]{64}$'),
  CONSTRAINT "WebSession_expiry_order_check" CHECK ("expiresAt" > "createdAt"),
  CONSTRAINT "WebSession_rotationCounter_nonnegative_check"
    CHECK ("rotationCounter" >= 0),
  CONSTRAINT "WebSession_version_positive_check" CHECK ("version" > 0),
  CONSTRAINT "WebSession_accountVersion_positive_check"
    CHECK ("accountVersion" > 0),
  CONSTRAINT "WebSession_replacement_not_self_check"
    CHECK ("replacedBySessionId" IS NULL OR "replacedBySessionId" <> "id")
);

CREATE TABLE "AnonymousIdentity" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "secretHash" CHAR(64) NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "lastSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "revokedAt" TIMESTAMP(3),
  "claimedAt" TIMESTAMP(3),
  "claimedAccountId" UUID,
  "version" INTEGER NOT NULL DEFAULT 1,

  CONSTRAINT "AnonymousIdentity_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "AnonymousIdentity_secretHash_format_check"
    CHECK ("secretHash" ~ '^[0-9a-f]{64}$'),
  CONSTRAINT "AnonymousIdentity_expiry_order_check"
    CHECK ("expiresAt" > "createdAt"),
  CONSTRAINT "AnonymousIdentity_version_positive_check" CHECK ("version" > 0)
);

CREATE INDEX "Account_status_idx" ON "Account"("status");
CREATE INDEX "Account_deletionRequestedAt_idx"
  ON "Account"("deletionRequestedAt");

CREATE UNIQUE INDEX "AuthIdentity_provider_providerSubject_key"
  ON "AuthIdentity"("provider", "providerSubject");
CREATE INDEX "AuthIdentity_accountId_idx" ON "AuthIdentity"("accountId");

CREATE UNIQUE INDEX "WebSession_tokenHash_key" ON "WebSession"("tokenHash");
CREATE UNIQUE INDEX "WebSession_replacedBySessionId_key"
  ON "WebSession"("replacedBySessionId");
CREATE INDEX "WebSession_accountId_revokedAt_idx"
  ON "WebSession"("accountId", "revokedAt");
CREATE INDEX "WebSession_expiresAt_idx" ON "WebSession"("expiresAt");
CREATE INDEX "WebSession_lastSeenAt_idx" ON "WebSession"("lastSeenAt");

CREATE UNIQUE INDEX "AnonymousIdentity_secretHash_key"
  ON "AnonymousIdentity"("secretHash");
CREATE INDEX "AnonymousIdentity_expiresAt_idx"
  ON "AnonymousIdentity"("expiresAt");
CREATE INDEX "AnonymousIdentity_revokedAt_idx"
  ON "AnonymousIdentity"("revokedAt");
CREATE INDEX "AnonymousIdentity_claimedAccountId_idx"
  ON "AnonymousIdentity"("claimedAccountId");

ALTER TABLE "AuthIdentity"
  ADD CONSTRAINT "AuthIdentity_accountId_fkey"
  FOREIGN KEY ("accountId") REFERENCES "Account"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "WebSession"
  ADD CONSTRAINT "WebSession_accountId_fkey"
  FOREIGN KEY ("accountId") REFERENCES "Account"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "WebSession"
  ADD CONSTRAINT "WebSession_replacedBySessionId_fkey"
  FOREIGN KEY ("replacedBySessionId") REFERENCES "WebSession"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "AnonymousIdentity"
  ADD CONSTRAINT "AnonymousIdentity_claimedAccountId_fkey"
  FOREIGN KEY ("claimedAccountId") REFERENCES "Account"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

COMMIT;
