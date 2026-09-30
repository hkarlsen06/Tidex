import { deepStrictEqual as assertEquals, rejects } from "node:assert/strict";
import { Buffer } from "node:buffer";
import { Environment } from "@apple/app-store-server-library";
import { KEYUTIL, KJUR } from "npm:jsrsasign@11.1.3";
import { DenoSignedDataVerifier } from "./deno-signed-data-verifier.ts";

const BUNDLE_ID = "no.tidex.app";
// Apple marks its leaf and intermediate certificates with these extensions and
// the verifier requires them.
const LEAF_OID = "1.2.840.113635.100.6.11.1";
const INTERMEDIATE_OID = "1.2.840.113635.100.6.2.1";

type Authority = {
  cn: string;
  // deno-lint-ignore no-explicit-any
  keys: any;
  der: Buffer;
};

type CertOptions = {
  isCA: boolean;
  appleOid?: string;
  notAfter?: string;
};

function newKeys() {
  return KEYUTIL.generateKeypair("EC", "secp256r1");
}

function newCertificate(
  subjectCn: string,
  // deno-lint-ignore no-explicit-any
  subjectKeys: any,
  issuerCn: string,
  // deno-lint-ignore no-explicit-any
  issuerKeys: any,
  options: CertOptions,
): Buffer {
  const ext: { extname: string; [key: string]: unknown }[] = [
    { extname: "basicConstraints", cA: options.isCA },
  ];
  if (options.appleOid) {
    ext.push({ extname: options.appleOid, extn: "0500" });
  }
  const certificate = new KJUR.asn1.x509.Certificate({
    version: 3,
    serial: { int: Math.floor(Math.random() * 1_000_000) + 1 },
    issuer: { str: `/CN=${issuerCn}` },
    subject: { str: `/CN=${subjectCn}` },
    notbefore: "20200101000000Z",
    notafter: options.notAfter ?? "20500101000000Z",
    sbjpubkey: subjectKeys.pubKeyObj,
    ext,
    sigalg: "SHA256withECDSA",
    cakey: issuerKeys.prvKeyObj,
  });
  return Buffer.from(certificate.getEncodedHex(), "hex");
}

function newRoot(cn: string): Authority {
  const keys = newKeys();
  const der = newCertificate(cn, keys, cn, keys, { isCA: true });
  return { cn, keys, der };
}

type Chain = {
  ders: Buffer[];
  // deno-lint-ignore no-explicit-any
  leafKeys: any;
};

function newChain(
  root: Authority,
  options: {
    leaf?: Partial<CertOptions>;
    intermediate?: Partial<CertOptions>;
  } = {},
): Chain {
  const intermediateKeys = newKeys();
  const leafKeys = newKeys();
  const intermediate = newCertificate(
    "Test Intermediate",
    intermediateKeys,
    root.cn,
    root.keys,
    { isCA: true, appleOid: INTERMEDIATE_OID, ...options.intermediate },
  );
  const leaf = newCertificate(
    "Test Leaf",
    leafKeys,
    "Test Intermediate",
    intermediateKeys,
    { isCA: false, appleOid: LEAF_OID, ...options.leaf },
  );
  return { ders: [leaf, intermediate, root.der], leafKeys };
}

function base64url(value: string | Uint8Array): string {
  return Buffer.from(value).toString("base64url");
}

async function signJws(
  chain: Chain,
  payload: Record<string, unknown>,
): Promise<string> {
  const header = {
    alg: "ES256",
    x5c: chain.ders.map((der) => der.toString("base64")),
  };
  const signingInput = `${base64url(JSON.stringify(header))}.${
    base64url(JSON.stringify(payload))
  }`;
  const pkcs8 = KEYUTIL.getPEM(chain.leafKeys.prvKeyObj, "PKCS8PRV")
    .replace(/-----[A-Z ]+-----|\s/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Buffer.from(pkcs8, "base64"),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    Buffer.from(signingInput),
  );
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

function notificationPayload(): Record<string, unknown> {
  return {
    notificationType: "TEST",
    notificationUUID: "00000000-0000-4000-8000-000000000000",
    data: { environment: "Sandbox", bundleId: BUNDLE_ID },
    version: "2.0",
    signedDate: Date.now(),
  };
}

function verifierFor(root: Authority): DenoSignedDataVerifier {
  return new DenoSignedDataVerifier(
    [root.der],
    false,
    Environment.SANDBOX,
    BUNDLE_ID,
  );
}

const trustedRoot = newRoot("Trusted Test Root");

Deno.test("accepts a correctly anchored chain", async () => {
  const jws = await signJws(newChain(trustedRoot), notificationPayload());
  const decoded = await verifierFor(trustedRoot).verifyAndDecodeNotification(
    jws,
  );
  assertEquals(decoded.notificationType, "TEST");
});

Deno.test("rejects a tampered payload", async () => {
  const jws = await signJws(newChain(trustedRoot), notificationPayload());
  const [header, , signature] = jws.split(".");
  const forged = base64url(
    JSON.stringify({ ...notificationPayload(), notificationType: "REFUND" }),
  );
  await rejects(
    verifierFor(trustedRoot).verifyAndDecodeNotification(
      `${header}.${forged}.${signature}`,
    ),
  );
});

Deno.test("rejects a chain anchored to a different root", async () => {
  const otherRoot = newRoot("Other Test Root");
  const jws = await signJws(newChain(otherRoot), notificationPayload());
  await rejects(verifierFor(trustedRoot).verifyAndDecodeNotification(jws));
});

Deno.test("rejects a self-signed leaf repeated as the chain", async () => {
  const leafKeys = newKeys();
  const selfSigned = newCertificate(
    "Self Signed",
    leafKeys,
    "Self Signed",
    leafKeys,
    { isCA: false, appleOid: LEAF_OID },
  );
  const chain = { ders: [selfSigned, selfSigned, selfSigned], leafKeys };
  const jws = await signJws(chain, notificationPayload());
  await rejects(verifierFor(trustedRoot).verifyAndDecodeNotification(jws));
});

Deno.test("rejects a leaf that is a CA", async () => {
  const chain = newChain(trustedRoot, { leaf: { isCA: true } });
  const jws = await signJws(chain, notificationPayload());
  await rejects(verifierFor(trustedRoot).verifyAndDecodeNotification(jws));
});

Deno.test("rejects an intermediate that is not a CA", async () => {
  const chain = newChain(trustedRoot, { intermediate: { isCA: false } });
  const jws = await signJws(chain, notificationPayload());
  await rejects(verifierFor(trustedRoot).verifyAndDecodeNotification(jws));
});

Deno.test("rejects a leaf without the Apple extension", async () => {
  const chain = newChain(trustedRoot, { leaf: { appleOid: undefined } });
  const jws = await signJws(chain, notificationPayload());
  await rejects(verifierFor(trustedRoot).verifyAndDecodeNotification(jws));
});

Deno.test("rejects a leaf that expired before the signed date", async () => {
  const chain = newChain(trustedRoot, {
    leaf: { notAfter: "20210101000000Z" },
  });
  const jws = await signJws(chain, notificationPayload());
  await rejects(verifierFor(trustedRoot).verifyAndDecodeNotification(jws));
});
