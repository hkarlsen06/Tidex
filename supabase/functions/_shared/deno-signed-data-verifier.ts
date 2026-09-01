// Apple's SignedDataVerifier relies on node:crypto X509Certificate APIs
// (raw, verify, toString) and on jsonwebtoken key checks that the self-hosted
// Supabase edge runtime (Deno 2.1) does not implement. This subclass keeps the
// same checks but does the certificate and JWS work with jsrsasign parsing plus
// native node:crypto verification.
import { Buffer } from "node:buffer";
import {
  createPublicKey,
  type KeyObject,
  verify as verifyNativeSignature,
  type X509Certificate,
} from "node:crypto";
import {
  Environment,
  SignedDataVerifier,
  VerificationException,
  VerificationStatus,
} from "@apple/app-store-server-library";
import { ASN1HEX, KEYUTIL, X509 as JSRX509 } from "npm:jsrsasign@11.1.3";

// Supabase's Deno runtime does not implement X509Certificate.toString(),
// verify(), or raw (self-hosted edge-runtime on Deno 2.1), so keep the DER
// bytes ourselves and run the same pure-JS certificate checks as Apple's
// verifier with jsrsasign.
export class DenoSignedDataVerifier extends SignedDataVerifier {
  private readonly rootDers: Buffer[];
  private currentChainDers: Buffer[] = [];

  constructor(
    appleRootCertificates: Buffer[],
    enableOnlineChecks: boolean,
    environment: Environment,
    bundleId: string,
    appAppleId?: number,
  ) {
    super(
      appleRootCertificates,
      enableOnlineChecks,
      environment,
      bundleId,
      appAppleId,
    );
    this.rootDers = appleRootCertificates;
  }

  // The library's own verifyJWT hands the leaf key to jsonwebtoken, which
  // rejects Deno KeyObjects ("ES256 requires curve prime256v1"), so the JWS
  // signature is checked here with native node:crypto instead.
  protected override async verifyJWT<T>(
    jwt: string,
    // deno-lint-ignore no-explicit-any
    validator: any,
    signedDateExtractor: (decodedJWT: T) => Date,
  ): Promise<T> {
    try {
      const [encodedHeader, encodedPayload, encodedSignature] = jwt.split(".");
      if (!encodedHeader || !encodedPayload || !encodedSignature) {
        throw new VerificationException(VerificationStatus.VERIFICATION_FAILURE);
      }
      const decodedJWT = JSON.parse(
        Buffer.from(encodedPayload, "base64url").toString("utf8"),
      ) as T;
      if (!validator.validate(decodedJWT)) {
        throw new VerificationException(VerificationStatus.FAILURE);
      }
      // deno-lint-ignore no-explicit-any
      const environment = (this as any).environment as Environment;
      if (
        environment === Environment.XCODE ||
        environment === Environment.LOCAL_TESTING
      ) {
        return decodedJWT;
      }
      const header = JSON.parse(
        Buffer.from(encodedHeader, "base64url").toString("utf8"),
      );
      const chain: string[] = Array.isArray(header?.x5c) ? header.x5c : [];
      if (chain.length !== 3) {
        throw new VerificationException(VerificationStatus.INVALID_CHAIN_LENGTH);
      }
      if (header?.alg !== "ES256") {
        throw new VerificationException(VerificationStatus.VERIFICATION_FAILURE);
      }
      this.currentChainDers = chain.slice(0, 2).map((certificate) =>
        Buffer.from(certificate, "base64")
      );
      // deno-lint-ignore no-explicit-any
      const effectiveDate = (this as any).enableOnlineChecks
        ? new Date()
        : signedDateExtractor(decodedJWT);
      const publicKey = await this.verifyCertificateChain(
        // deno-lint-ignore no-explicit-any
        [] as any,
        // deno-lint-ignore no-explicit-any
        undefined as any,
        // deno-lint-ignore no-explicit-any
        undefined as any,
        effectiveDate,
      );
      const signature = Buffer.from(encodedSignature, "base64url");
      if (signature.length !== 64) {
        throw new VerificationException(VerificationStatus.VERIFICATION_FAILURE);
      }
      const verified = verifyNativeSignature(
        "sha256",
        Buffer.from(`${encodedHeader}.${encodedPayload}`),
        publicKey,
        concatSignatureToDer(signature),
      );
      if (!verified) {
        throw new VerificationException(VerificationStatus.VERIFICATION_FAILURE);
      }
      return decodedJWT;
    } catch (error) {
      if (error instanceof VerificationException) {
        throw error;
      }
      if (error instanceof Error) {
        throw new VerificationException(
          VerificationStatus.VERIFICATION_FAILURE,
          error,
        );
      }
      throw new VerificationException(VerificationStatus.VERIFICATION_FAILURE);
    }
  }

  protected override verifyCertificateChain(
    _trustedRoots: X509Certificate[],
    _leaf: X509Certificate,
    _intermediate: X509Certificate,
    effectiveDate: Date,
  ): Promise<KeyObject> {
    const [leafDer, intermediateDer] = this.currentChainDers;
    if (!leafDer || !intermediateDer) {
      throw new VerificationException(VerificationStatus.VERIFICATION_FAILURE);
    }
    const cacheKey = `${leafDer.toString("hex")}:${intermediateDer.toString("hex")}`;
    const cached = verifiedChainCache.get(cacheKey);
    if (cached !== undefined) {
      return Promise.resolve(cached);
    }
    const jsLeaf = jsCertificate(leafDer);
    const jsIntermediate = jsCertificate(intermediateDer);
    const jsRoot = this.rootDers.map(jsCertificate).find((candidate) =>
      jsIntermediate.getIssuerHex() === candidate.getSubjectHex() &&
      certificateSignedBy(jsIntermediate, candidate)
    );
    const valid = jsRoot !== undefined &&
      jsLeaf.getIssuerHex() === jsIntermediate.getSubjectHex() &&
      certificateSignedBy(jsLeaf, jsIntermediate) &&
      jsIntermediate.getExtBasicConstraints()?.cA === true &&
      jsLeaf.getExtInfo("1.2.840.113635.100.6.11.1") !== undefined &&
      jsIntermediate.getExtInfo("1.2.840.113635.100.6.2.1") !== undefined;

    if (!valid) {
      throw new VerificationException(VerificationStatus.VERIFICATION_FAILURE);
    }

    for (const certificate of [jsLeaf, jsIntermediate, jsRoot]) {
      if (
        zuluToDate(certificate.getNotBefore()).getTime() >
            effectiveDate.getTime() + 60_000 ||
        zuluToDate(certificate.getNotAfter()).getTime() <
            effectiveDate.getTime() - 60_000
      ) {
        throw new VerificationException(VerificationStatus.INVALID_CERTIFICATE);
      }
    }

    const publicKey = createPublicKey(KEYUTIL.getPEM(jsLeaf.getPublicKey()));
    verifiedChainCache.set(cacheKey, publicKey);
    return Promise.resolve(publicKey);
  }
}

const verifiedChainCache = new Map<string, KeyObject>();

// jsrsasign's pure-JS signature checks take seconds per certificate, and its
// getIssuerString()/getSignatureAlgorithmField() helpers spin indefinitely on
// the self-hosted runtime, so compare DN bytes directly, read the signature
// algorithm OID, and hand the verification to native node:crypto.
const SIGNATURE_ALGORITHM_HASHES: Record<string, string> = {
  "1.2.840.10045.4.3.2": "sha256", // ecdsa-with-SHA256
  "1.2.840.10045.4.3.3": "sha384", // ecdsa-with-SHA384
  "1.2.840.10045.4.3.4": "sha512", // ecdsa-with-SHA512
  "1.2.840.113549.1.1.11": "sha256", // sha256WithRSAEncryption
  "1.2.840.113549.1.1.12": "sha384", // sha384WithRSAEncryption
  "1.2.840.113549.1.1.13": "sha512", // sha512WithRSAEncryption
};

function certificateSignedBy(certificate: JSRX509, issuer: JSRX509): boolean {
  try {
    const algorithmOid = ASN1HEX.hextooidstr(
      ASN1HEX.getVbyList(certificate.hex, 0, [1, 0], "06"),
    );
    const hash = SIGNATURE_ALGORITHM_HASHES[algorithmOid];
    const tbsHex = ASN1HEX.getTLVbyList(certificate.hex, 0, [0]);
    if (!hash || typeof tbsHex !== "string") {
      return false;
    }
    return verifyNativeSignature(
      hash,
      Buffer.from(tbsHex, "hex"),
      createPublicKey(KEYUTIL.getPEM(issuer.getPublicKey())),
      Buffer.from(certificate.getSignatureValueHex(), "hex"),
    );
  } catch {
    return false;
  }
}

// JWS carries ECDSA signatures as raw r||s; node:crypto expects DER.
function concatSignatureToDer(signature: Buffer): Buffer {
  const encodeInteger = (bytes: Buffer): Buffer => {
    let start = 0;
    while (start < bytes.length - 1 && bytes[start] === 0) {
      start += 1;
    }
    let body = bytes.subarray(start);
    if (body[0] & 0x80) {
      body = Buffer.concat([Buffer.from([0]), body]);
    }
    return Buffer.concat([Buffer.from([0x02, body.length]), body]);
  };
  const r = encodeInteger(signature.subarray(0, 32));
  const s = encodeInteger(signature.subarray(32));
  return Buffer.concat([Buffer.from([0x30, r.length + s.length]), r, s]);
}

function jsCertificate(der: Buffer): JSRX509 {
  const parsed = new JSRX509();
  parsed.readCertHex(der.toString("hex"));
  return parsed;
}

// jsrsasign returns validity as UTCTime (YYMMDDHHMMSSZ) or GeneralizedTime
// (YYYYMMDDHHMMSSZ).
function zuluToDate(zulu: string): Date {
  const digits = zulu.replace(/Z$/, "");
  const full = digits.length === 12
    ? (Number(digits.slice(0, 2)) >= 50 ? "19" : "20") + digits
    : digits;
  return new Date(Date.UTC(
    Number(full.slice(0, 4)),
    Number(full.slice(4, 6)) - 1,
    Number(full.slice(6, 8)),
    Number(full.slice(8, 10)),
    Number(full.slice(10, 12)),
    Number(full.slice(12, 14)),
  ));
}
