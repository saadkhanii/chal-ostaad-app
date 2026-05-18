const { setGlobalOptions } = require("firebase-functions");
const { onRequest } = require("firebase-functions/https");
const logger = require("firebase-functions/logger");
const stripe = require("stripe")(process.env.STRIPE_SECRET_KEY);
const admin = require("firebase-admin");

admin.initializeApp();

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
    const amountInCents = Math.round((amount / 280) * 100);
    const paymentIntent = await stripe.paymentIntents.create({
      amount: amountInCents,
      currency: "usd",
      metadata: { jobId: jobId || "", clientId: clientId || "" },
      automatic_payment_methods: { enabled: true },
    });
    logger.info(`PaymentIntent created: ${paymentIntent.id}`);
    res.status(200).json({ clientSecret: paymentIntent.client_secret, paymentIntentId: paymentIntent.id });
  } catch (error) {
    logger.error("Stripe error:", error.message);
    res.status(500).json({ error: error.message });
  }
});

// ── Timeout checker (call via Cloud Scheduler every minute) ──
exports.checkTimeouts = onRequest(async (req, res) => {
  try {
    const now = admin.firestore.Timestamp.now();
    const jobsRef = admin.firestore().collection("jobs");

    // 1. Expired grace periods
    const graceExpired = await jobsRef.where("status", "==", "grace_period").where("gracePeriodExpiry", "<=", now).get();
    for (const doc of graceExpired.docs) {
      const data = doc.data();
      logger.info(`Finalising acceptance for job ${doc.id} (grace period expired)`);
      const acceptedBid = await admin.firestore().collection("bids").where("jobId", "==", doc.id).where("status", "==", "accepted").limit(1).get();
      if (acceptedBid.docs.isEmpty) continue;
      const workerId = acceptedBid.docs[0].data().workerId;
      const batch = admin.firestore().batch();
      const otherBids = await admin.firestore().collection("bids").where("jobId", "==", doc.id).where("status", "==", "pending").get();
      for (const bid of otherBids.docs) {
        batch.update(bid.ref, { status: "rejected", updatedAt: now });
      }
      const isUrgent = data.isUrgent || false;
      let newStatus = isUrgent ? "active" : "scheduled";
      const updates = {
        status: newStatus,
        gracePeriodExpiry: admin.firestore.FieldValue.delete(),
        updatedAt: now,
      };
      if (isUrgent) {
        updates.workerStartDeadline = admin.firestore.Timestamp.fromDate(new Date(Date.now() + 10 * 60 * 1000));
      } else {
        // For scheduled jobs: set workerStartDeadline = scheduledAt + 2 hours
        const scheduledAt = data.scheduledAt;
        if (scheduledAt) {
          const deadline = scheduledAt.toDate();
          deadline.setHours(deadline.getHours() + 2);
          updates.workerStartDeadline = admin.firestore.Timestamp.fromDate(deadline);
        }
      }
      batch.update(doc.ref, updates);
      await batch.commit();
      // Notify worker that job is ready
      const workerToken = await admin.firestore().collection("users").doc(workerId).get();
      if (workerToken.exists && workerToken.data()?.fcmToken) {
        // send push notification (optional)
      }
    }

    // 2. Expired worker start deadlines (active or scheduled jobs)
    const deadlineExpired = await jobsRef.where("status", "in", ["active", "scheduled"]).where("workerStartDeadline", "<=", now).get();
    for (const doc of deadlineExpired.docs) {
      const data = doc.data();
      const acceptedBid = await admin.firestore().collection("bids").where("jobId", "==", doc.id).where("status", "==", "accepted").limit(1).get();
      if (acceptedBid.docs.isEmpty) continue;
      const workerId = acceptedBid.docs[0].data().workerId;
      const batch = admin.firestore().batch();
      batch.update(doc.ref, {
        status: "open",
        isUrgent: true,
        reopenedAs: "urgent",
        workerStartDeadline: admin.firestore.FieldValue.delete(),
        bannedWorkerIds: admin.firestore.FieldValue.arrayUnion(workerId),
        cancelledBy: "worker_no_action",
        cancelledAt: now,
        updatedAt: now,
      });
      await batch.commit();
      logger.info(`Worker ${workerId} no-action timeout for job ${doc.id}, job reopened as urgent`);
    }

    res.status(200).send("OK");
  } catch (error) {
    logger.error("Timeout check error:", error);
    res.status(500).send(error.message);
  }
});