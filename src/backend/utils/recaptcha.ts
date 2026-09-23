// src/backend/utils/recaptcha.ts

// Verifies a Google reCAPTCHA v2 token server-side. Requires
// RECAPTCHA_SECRET_KEY in the environment (paired with
// NEXT_PUBLIC_RECAPTCHA_SITE_KEY on the frontend).
export async function verifyRecaptcha(token: string, remoteIp: string): Promise<boolean> {
  const secret = process.env.RECAPTCHA_SECRET_KEY;
  if (!secret) {
    console.error("RECAPTCHA_SECRET_KEY is not configured.");
    return false;
  }

  try {
    const params = new URLSearchParams({
      secret,
      response: token,
      remoteip: remoteIp,
    });

    const res = await fetch("https://www.google.com/recaptcha/api/siteverify", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: params.toString(),
    });

    const data = (await res.json()) as { success: boolean };
    return data.success === true;
  } catch (err) {
    console.error("reCAPTCHA verification failed:", err);
    return false;
  }
}