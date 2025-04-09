import chromium from "chrome-aws-lambda";
import puppeteer from "puppeteer-core";
import { S3 } from "aws-sdk";
// @ts-ignore
import { startFlow } from "lighthouse/lighthouse-core/fraggle-rock/api.js";

export const handler = async (event: any, context: any) => {
  console.log("Event:", event);

  const body = JSON.parse(event.body || "{}");
  const urls: string[] = body.urls;
  const studentId: string = body.student_id

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

  const browser = await puppeteer.launch({
    args: chromium.args,
    defaultViewport: chromium.defaultViewport,
    executablePath: await chromium.executablePath,
    headless: chromium.headless,
    timeout: 120000,
  });

  const page = await browser.newPage();

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const name = `lighthouse-${timestamp}`;
  const flow = await startFlow(page, { name });

  for (const url of urls) {
    await flow.navigate(url)
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
