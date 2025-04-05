import type { Arguments, CommandBuilder } from "yargs";
import puppeteer from "puppeteer";
import { writeFileSync } from "fs";
// @ts-ignore
import { startFlow } from "lighthouse/lighthouse-core/fraggle-rock/api.js";

type Options = {
  urls?: string[];
};

export const builder: CommandBuilder<Options, Options> = (yargs) =>
  yargs.options({
    files: { array: true, string: true },
    urls: { array: true, string: true },
  });

export const handler = async (argv: Arguments<Options>): Promise<void> => {
  const name = new Date().toString();
  if (argv.urls && argv.urls.length > 0) {
    const browser = await puppeteer.launch({
      headless: true,
      timeout: 120000
    });
    const page = await browser.newPage();

    const flow = await startFlow(page, { name });

    for (const url of argv.urls) {
      await flow.navigate(url)
    }
    
    await browser.close();

    const report = flow.generateReport();
    writeFileSync(`${name}.html`, report);
  }
  process.exit(0);
};
