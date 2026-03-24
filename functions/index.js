const admin = require('firebase-admin');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const logger = require('firebase-functions/logger');

admin.initializeApp();

function toSafeString(value, fallback = '') {
  if (typeof value === 'string') {
    return value.trim();
  }
  if (value === null || value === undefined) {
    return fallback;
  }
  return String(value).trim();
}

function toSafeBoolean(value) {
  return Boolean(value);
}

async function deleteByField(collectionName, field, value) {
  const db = admin.firestore();
  const snapshot = await db
    .collection(collectionName)
    .where(field, '==', value)
    .get();

  if (snapshot.empty) return 0;

  let deleted = 0;
  let batch = db.batch();
  let ops = 0;

  for (const doc of snapshot.docs) {
    batch.delete(doc.ref);
    deleted += 1;
    ops += 1;

    if (ops === 450) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }

  if (ops > 0) {
    await batch.commit();
  }

  return deleted;
}

exports.syncUpdateCheckerToRemoteConfig = onDocumentWritten(
  'app_config/update_checker',
  async (event) => {
    const afterData = event.data?.after?.data();

    if (!afterData) {
      logger.info('update_checker document deleted; skipping Remote Config sync.');
      return;
    }

    const latestVersion = toSafeString(afterData.latest_version, '1.0.0');
    const updateUrl = toSafeString(afterData.update_url, '');
    const forceUpdate = toSafeBoolean(afterData.force_update);
    const updateMessage = toSafeString(afterData.update_message, '');

    const remoteConfig = admin.remoteConfig();

    try {
      const template = await remoteConfig.getTemplate();

      template.parameters = {
        ...(template.parameters || {}),
        latest_version: {
          defaultValue: { value: latestVersion },
        },
        update_url: {
          defaultValue: { value: updateUrl },
        },
        force_update: {
          defaultValue: { value: forceUpdate ? 'true' : 'false' },
        },
        update_message: {
          defaultValue: { value: updateMessage },
        },
      };

      await remoteConfig.publishTemplate(template);

      logger.info('Remote Config synced from app_config/update_checker', {
        latest_version: latestVersion,
        force_update: forceUpdate,
      });
    } catch (error) {
      logger.error('Failed to sync update_checker to Remote Config', error);
      throw error;
    }
  },
);

exports.adminDeleteUserAccount = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'You must be signed in to perform this action.');
  }

  const requesterSnap = await admin.firestore().collection('users').doc(request.auth.uid).get();
  const requesterRole = requesterSnap.exists ? requesterSnap.data()?.role : null;
  if (requesterRole !== 'superadmin') {
    throw new HttpsError('permission-denied', 'Only superadmin can delete user accounts.');
  }

  const userId = toSafeString(request.data?.userId);
  if (!userId) {
    throw new HttpsError('invalid-argument', 'Missing userId.');
  }

  if (userId === request.auth.uid) {
    throw new HttpsError('failed-precondition', 'You cannot delete your own superadmin account from this action.');
  }

  const db = admin.firestore();

  const [postsDeleted, routesDeleted, feedbackDeleted, notificationsDeleted] = await Promise.all([
    deleteByField('posts', 'userId', userId),
    deleteByField('routes', 'contributorId', userId),
    deleteByField('feedbacks', 'userId', userId),
    deleteByField('notifications', 'userId', userId),
  ]);

  await db.collection('users').doc(userId).delete().catch((error) => {
    if (error?.code !== 5) {
      throw error;
    }
  });

  await admin.auth().deleteUser(userId).catch((error) => {
    if (error?.code !== 'auth/user-not-found') {
      throw error;
    }
  });

  logger.info('adminDeleteUserAccount completed', {
    deletedBy: request.auth.uid,
    userId,
    postsDeleted,
    routesDeleted,
    feedbackDeleted,
    notificationsDeleted,
  });

  return {
    ok: true,
    deleted: {
      posts: postsDeleted,
      routes: routesDeleted,
      feedbacks: feedbackDeleted,
      notifications: notificationsDeleted,
      userDoc: true,
      authUser: true,
    },
  };
});
