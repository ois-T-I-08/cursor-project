import "server-only";

export interface AccountIdentityFeatureState {
  readonly accountIdentityEnabled: boolean;
  readonly webAccountSessionEnabled: boolean;
}

function enabled(value: string | undefined): boolean {
  return value === "true";
}

export function accountIdentityFeatureState(
  env: Readonly<Record<string, string | undefined>> = process.env,
): AccountIdentityFeatureState {
  return {
    accountIdentityEnabled: enabled(env.ACCOUNT_IDENTITY_ENABLED),
    webAccountSessionEnabled: enabled(env.WEB_ACCOUNT_SESSION_ENABLED),
  };
}

export function isWebSessionIssuanceEnabled(
  state: AccountIdentityFeatureState = accountIdentityFeatureState(),
): boolean {
  return state.accountIdentityEnabled && state.webAccountSessionEnabled;
}
