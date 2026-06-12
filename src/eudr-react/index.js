// @vgsdk/eudr-react — punto de entrada.
// Componente de captura de certificaciones (render dinámico desde form-schema), offline-first,
// con antifraude y nivel de verificación. Para el APK VG Suite (#07) y el ERP (#03).
// AUTOCONTENIDO: la capa de captura (engine + antifraude + integridad) vive en ./capture (copia del
// repo del producto; mantener sincronizada con frontend/src/form-schemas/capture/ — fuente de verdad).

export { default as CertForm, readFormFromContainer } from './CertForm.jsx'
export { useCertCapture, buildAntifraudeCtxEUDR } from './useCertCapture.js'

export * as offlineEngine from './capture/cert-offline-engine.js'
export * as fraudRules from './capture/fraud-rules-engine.js'
export * as verification from './capture/verification-level.js'
export * as auditHashChain from './capture/audit-hash-chain.js'
export * as riskSampling from './capture/risk-based-sampling.js'

export { createCertOfflineEngine } from './capture/cert-offline-engine.js'
export { evaluateRules } from './capture/fraud-rules-engine.js'
export { computeVerifiedCompleteness, computeFieldLevel, applyFlagsToItems } from './capture/verification-level.js'
export { selectForInspection } from './capture/risk-based-sampling.js'
