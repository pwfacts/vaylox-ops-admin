import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createHmac } from "https://deno.land/std@0.168.0/node/crypto.ts";

console.log("ImageKit Signature Function Initialized");

serve(async (req) => {
    // Handle CORS
    if (req.method === "OPTIONS") {
        return new Response("ok", {
            headers: {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "POST",
                "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
            },
        });
    }

    try {
        const { token, expire } = await req.json();
        const privateKey = Deno.env.get("IMAGEKIT_PRIVATE_KEY");

        if (!privateKey) {
            throw new Error("Missing IMAGEKIT_PRIVATE_KEY environment variable");
        }

        // HMAC SHA-1 signature generation
        // ImageKit requires token + expire signed with private key
        const signature = createHmac("sha1", privateKey)
            .update(token + expire)
            .digest("hex");

        return new Response(
            JSON.stringify({ signature }),
            {
                headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
            },
        );
    } catch (error) {
        return new Response(
            JSON.stringify({ error: error.message }),
            {
                status: 400,
                headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
            },
        );
    }
});
