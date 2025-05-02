import puppeteer, { type LaunchOptions, type Browser } from "puppeteer";
import { S3 } from "aws-sdk";
import type { APIGatewayProxyEvent, Context } from "aws-lambda";
// @ts-ignore
import { startFlow } from "lighthouse/lighthouse-core/fraggle-rock/api.js";

export const handler = async (
  event: APIGatewayProxyEvent,
  context: Context
) => {
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
      XDG_CACHE_HOME: '/tmp/chrome-cache',
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
      // デフォルト 120000ms を 300000ms（5分）に延長
      configContext: {
        settingsOverrides: {
          maxWaitForLoad: 300_000,
          maxWaitForFcp: 300_000,
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

  return {
    statusCode: 200,
    body: JSON.stringify({
      message: "Report uploaded to S3 successfully",
      filename: `${studentId}/${name}.html`,
    }),
  };
};
