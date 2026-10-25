module LicenceIssuers
  # ============================================================
  # INTEGRATION POINT: Acme licence keys.
  #
  # Approving a Acme signup in the admin enqueues ApprovalJob, which calls
  # #issue. Until the licence-key work in licence-server lands, this issues
  # nothing: it returns nil, the signup stays "approved, licence not issued"
  # in the admin, and nobody is emailed.
  #
  # To fill it in (docs/adr/0001-self-hosted-waitlist.md, "Licence keys"):
  #
  # 1. Ask licence-server to issue a key for signup.email, over the internal
  #    Docker network (http://licence-server-origin:3000, never the public
  #    hostname), authenticated with a shared token read from a tmpfs file
  #    (ACME_LICENCE_TOKEN_FILE). Make the request idempotent on
  #    "waitlist-signup-#{signup.id}" so a retried job can't issue twice.
  # 2. Let licence-server deliver the key to the person (it owns the key and
  #    its revocation). This app must never store or log the key.
  # 3. Return the licence's id or label from licence-server as the reference.
  #    ApprovalJob stores it and the time in licence_issued_at.
  # 4. Raise on failure; the job retries with backoff, and the admin shows
  #    the signup as approved without a licence until it succeeds.
  # ============================================================
  class AcmeLicence
    def issue(signup)
      nil
    end
  end
end
