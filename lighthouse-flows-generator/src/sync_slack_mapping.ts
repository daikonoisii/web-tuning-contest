import { App } from '@slack/bolt';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';

// .env から環境変数を読み込む
dotenv.config({ path: path.resolve(__dirname, '../../.env') });
dotenv.config({ path: path.resolve(__dirname, '../../.env.admin') });

const slackToken = process.env.SLACK_BOT_TOKEN!;
const bucketName = process.env.S3_BUCKET_NAME!;
const objectKey =  process.env.MAPPING_S3_KEY || 'mapping.json';

// Bolt アプリ初期化
const app = new App({ token: slackToken, signingSecret: process.env.SLACK_SIGNING_SECRET! });

const s3Client = new S3Client({});

interface ParticipantEmail {
  studentId: string;
  email: string;
}

async function loadLocalMapping(): Promise<Record<string, string>> {
  // プロジェクトルート直下の participants_email.json を参照
  const filePath = path.resolve(__dirname, '../participants_email.json');
  if (!fs.existsSync(filePath)) {
    throw new Error(`participants_email.json が見つかりません: ${filePath}`);
  }
  const raw = fs.readFileSync(filePath, 'utf-8');
  const list: ParticipantEmail[] = JSON.parse(raw);
  const map: Record<string, string> = {};
  for (const { studentId, email } of list) {
    map[email.toLowerCase()] = studentId;
  }
  return map;
}

async function fetchAllSlackUsers() {
  const users: Array<{ id: string; profile?: { email?: string, name?: string } }> = [];
  let cursor: string | undefined;
  do {
    const res = await app.client.users.list({ cursor, limit: 200 });
    if (!res.members) break;
    for (const member of res.members) {
      if (!member.id) continue;
      users.push({ id: member.id,
                   profile: {
                      email: member.profile?.email,
                      // name: member.profile?.real_name_normalized
                    } });
    }
    cursor = res.response_metadata?.next_cursor;
  } while (cursor);
  // console.log('Fetched Slack users:', JSON.stringify(users, null, 2));
  return users;
}

async function buildMapping() {
  const localMap = await loadLocalMapping();
  const slackUsers = await fetchAllSlackUsers();
  const result: Record<string, string> = {};
  for (const user of slackUsers) {
    const email = user.profile?.email?.toLowerCase();
    if (email && localMap[email]) {
      result[user.id] = localMap[email];
    }
  }
  return result;
}

async function uploadMapping(mapping: Record<string, string>) {
  const body = JSON.stringify(mapping, null, 2);
  const cmd = new PutObjectCommand({ Bucket: bucketName, Key: objectKey, Body: body, ContentType: 'application/json' });
  await s3Client.send(cmd);
  console.log(`Uploaded to s3://${bucketName}/${objectKey}`);
}

(async () => {
  try {
    console.log('Start mapping sync...');
    const mapping = await buildMapping();
    await uploadMapping(mapping);
    console.log('Completed.');
    process.exit(0);
  } catch (err) {
    console.error('Error:', err);
    process.exit(1);
  }
})();
