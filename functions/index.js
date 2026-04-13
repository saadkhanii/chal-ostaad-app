/**
 * Firebase Cloud Functions - Stripe Payment Integration
 * File: functions/index.js
 * Secret key is stored in .env file (never commit .env to git)
 */

const { setGlobalOptions } = require("firebase-functions");
const { onRequest }        = require("firebase-functions/https");
const logger               = require("firebase-functions/logger");
const stripe               = require("stripe")(process.env.STRIPE_SECRET_KEY);

setGlobalOptions({ maxInstances: 10 });

exports.createPaymentIntent = onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  try {
    const { amount, currency, jobId, clientId } = req.body;

    if (!amount || amount <= 0) {
      res.status(400).json({ error: "Invalid amount" });
      return;
    }

    logger.info(`Creating PaymentIntent: amount=${amount}, jobId=${jobId}`);

    // Convert PKR to USD cents (1 USD ≈ 280 PKR)
    const amountInCents = Math.round((amount / 280) * 100);

    const paymentIntent = await stripe.paymentIntents.create({
      amount:   amountInCents,
      currency: "usd",
      metadata: {
        jobId:    jobId    || "",
        clientId: clientId || "",
      },
      automatic_payment_methods: { enabled: true },
    });

    logger.info(`PaymentIntent created: ${paymentIntent.id}`);

    res.status(200).json({
      clientSecret:    paymentIntent.client_secret,
      paymentIntentId: paymentIntent.id,
    });
  } catch (error) {
    logger.error("Stripe error:", error.message);
    res.status(500).json({ error: error.message });
  }
});