import { createClient } from '@supabase/supabase-js';
import { config } from 'dotenv';
config({ path: '.env.migrate' });

const source = createClient(process.env.SOURCE_URL, process.env.SOURCE_SERVICE_KEY);
const target = createClient(process.env.TARGET_URL, process.env.TARGET_SERVICE_KEY);

const BUCKETS = ['media', 'documents', 'chat_attachments'];

// Recursively list every file path in a bucket (Storage list() only does one folder level at a time)
async function listAllFiles(client, bucket, prefix = '') {
  const { data, error } = await client.storage.from(bucket).list(prefix, { limit: 1000 });
  if (error) throw error;

  let files = [];
  for (const item of data) {
    const fullPath = prefix ? `${prefix}/${item.name}` : item.name;
    if (item.id === null) {
      // it's a folder — recurse into it
      files = files.concat(await listAllFiles(client, bucket, fullPath));
    } else {
      files.push(fullPath);
    }
  }
  return files;
}

async function migrateBucket(bucket) {
  console.log(`\n--- ${bucket} ---`);
  const paths = await listAllFiles(source, bucket);
  console.log(`Found ${paths.length} files`);

  let ok = 0, failed = [];
  for (const path of paths) {
    try {
      const { data: blob, error: dlErr } = await source.storage.from(bucket).download(path);
      if (dlErr) throw dlErr;

      const { error: upErr } = await target.storage.from(bucket).upload(path, blob, {
        upsert: true,
        contentType: blob.type || 'application/octet-stream',
      });
      if (upErr) throw upErr;

      ok++;
      process.stdout.write(`\r  ${ok}/${paths.length}`);
    } catch (err) {
      failed.push({ path, error: err.message });
    }
  }
  console.log(`\n  Done: ${ok} succeeded, ${failed.length} failed`);
  if (failed.length) failed.forEach(f => console.log(`  FAILED: ${f.path} — ${f.error}`));
}

for (const bucket of BUCKETS) {
  await migrateBucket(bucket);
}