import puppeteer, { type LaunchOptions, type Browser } from "puppeteer";
import { S3 } from "aws-sdk";
import { App } from '@slack/bolt';
import fs from 'node:fs';
import type { APIGatewayProxyEvent, Context } from "aws-lambda";
// @ts-ignore
import { startFlow } from "lighthouse/lighthouse-core/fraggle-rock/api.js";

async function sendSlackReport(
  s3: S3,
  bucketName: string,
  mappingKey: string,
  studentId: string,
  reportHtml: string,
  reportName: string
): Promise<void> {
  // マッピングファイルを S3 から取得
  const mappingData = await s3
    .getObject({ Bucket: bucketName, Key: mappingKey })
    .promise();

  if (!mappingData.Body) {
    console.error(`Failed to load mapping file: ${mappingKey}`);
    return;
  }

  const mappingJson = JSON.parse(
    mappingData.Body.toString("utf-8")
  ) as Record<string, string>;

  // studentId に紐づく Slack ID を取得
  const slackIds = Object.entries(mappingJson)
    .filter(([, sid]) => sid === studentId)
    .map(([slackId]) => slackId);

  if (slackIds.length === 0) {
    console.warn(`No Slack ID found for studentId=${studentId}`);
    return;
  }

  // Bolt アプリ初期化
  const slackApp = new App({
    token: process.env.SLACK_BOT_TOKEN,
    signingSecret: process.env.SLACK_SIGNING_SECRET,
  });

  for (const slackId of slackIds) {
    const conv = await slackApp.client.conversations.open({ users: slackId });
    const dmChannelId = conv.channel?.id;
    if (!dmChannelId) {
      console.error(`Cannot open DM channel for user ${slackId}`);
      continue;
    }

    await slackApp.client.files.uploadV2({
      file: Buffer.from(reportHtml, 'utf-8'),
      filename: `${reportName}.html`,
      initial_comment: `フローレポート${reportName}.html`,
      channels: dmChannelId,
    });

    console.log(`Uploaded HTML report to Slack ID ${slackId}`);(`Uploaded HTML report to Slack ID ${slackId}`);
  }
}

export const handler = async (
  event: APIGatewayProxyEvent,
  context: Context
) => {
  const userDataDir = '/tmp/chrome-user-data';
  // tmp/chrome-user-dataをクリア
  if (fs.existsSync(userDataDir)) {
    fs.rmSync(userDataDir, { recursive: true, force: true });
  }
  fs.mkdirSync(userDataDir, { recursive: true });

  console.log("Event:", event);

  const body = typeof event.body === 'string'
    ? JSON.parse(event.body)
    : event.body || event;

  const urls: string[] = body.urls;
  const studentId: string = body.student_id;

  const s3 = new S3();

  if (!urls || urls.length === 0) {
    return {
      statusCode: 400,
      body: JSON.stringify({ error: "No URLs provided" }),
    };
  }

  if (!studentId || studentId.length === 0) {
    return {
      statusCode: 400,
      body: JSON.stringify({ error: "No student ID" }),
    };
  }

  const options: LaunchOptions & { ignoreHTTPSErrors?: boolean } = {
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--single-process',
      '--disable-gpu',
      '--no-zygote',
      '--user-data-dir=/tmp/chrome-user-data',
    ],
    timeout: 60000,
    ignoreHTTPSErrors: true,
    executablePath: '/usr/bin/google-chrome-stable',
    dumpio: true,
    env: {
      ...process.env,
      HOME: '/tmp',
      XDG_CACHE_HOME: '/tmp/chrome-cache',
      XDG_CONFIG_HOME: '/tmp/.config',
    },
  };
  let browser: Browser;
  try {
    browser = await puppeteer.launch(options);
    console.log("ブラウザ起動成功");
  } catch (err) {
    console.error("ブラウザ起動失敗:", err);
    throw err;
  }
  console.timeEnd("chrome-launch-time");

  const page = await browser.newPage();

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const name = `lighthouse-${timestamp}`;
  const flow = await startFlow(
    page,
    {
      name,
      // デフォルト 120000ms を 240000ms（4分）に延長
      configContext: {
        settingsOverrides: {
          maxWaitForLoad: 240_000,
          maxWaitForFcp: 240_000,
        }
      }
    }
  );

  for (const url of urls) {
    console.log("計測開始：",url);
    await flow.navigate(url);
    console.log("計測完了：",url);
  }


  const report = await flow.generateReport();
  await browser.close();

  const bucketName = process.env.S3_BUCKET_NAME;

  if (!bucketName) {
    return {
      statusCode: 500,
      body: JSON.stringify({ error: "S3_BUCKET_NAME is not defined in env" }),
    };
  }

  await s3.putObject({
    Bucket: bucketName,
    Key: `${studentId}/${name}.html`,
    Body: report,
    ContentType: "text/html",
  }).promise();

  const mappingKey = process.env.MAPPING_S3_KEY;
  if (!mappingKey) {
    console.error("MAPPING_S3_KEY is not defined in env");
  } else {
    await sendSlackReport(
      s3,
      bucketName,
      mappingKey,
      studentId,
      report,
      name
    );
  }

  return {
    statusCode: 200,
    body: JSON.stringify({
      message: "Report uploaded to S3 successfully",
      filename: `${studentId}/${name}.html`,
    }),
  };
};
