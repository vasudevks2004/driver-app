// Run with Node.js from the repository root: node scripts/check-native-branding.mjs
// Validates checked-in resources only; it does not replace device cold-start tests.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {inflateSync} from 'node:zlib';
import {fileURLToPath} from 'node:url';
const root = new URL('../', import.meta.url);
const read = path => readFile(new URL(path, root));
const text = async path => (await read(path)).toString('utf8');
const crcTable = Array.from({length:256}, (_, n) => { let c=n; for(let i=0;i<8;i++) c=c&1?0xedb88320^(c>>>1):c>>>1; return c>>>0; });
const crc = data => {let c=0xffffffff; for(const v of data)c=crcTable[(c^v)&255]^(c>>>8);return (c^0xffffffff)>>>0;};
const resources = [
  [1, 'drawable-mdpi', 'LaunchImage.png'],
  [2, 'drawable-xhdpi', 'LaunchImage@2x.png'],
  [3, 'drawable-xxhdpi', 'LaunchImage@3x.png'],
];
for (const [scale, density, name] of resources) {
  const android = await read('android/app/src/main/res/'+density+'/hired_splash_logo.png');
  const ios = await read('ios/Runner/Assets.xcassets/LaunchImage.imageset/'+name);
  assert.deepEqual(android, ios, 'Both platforms must use the same rendered wordmark at each scale');
  assert.equal(ios.subarray(0,8).toString('hex'), '89504e470d0a1a0a');
  assert.equal(ios.readUInt32BE(16), 180*scale);
  assert.equal(ios.readUInt32BE(20), 60*scale);
  assert.equal(ios[24], 8); assert.equal(ios[25], 6, 'Use RGBA for a transparent splash wordmark');
  let at=8; const idat=[];
  while(at<ios.length){ const length=ios.readUInt32BE(at); const type=ios.subarray(at+4,at+8).toString('ascii'); const data=ios.subarray(at+8,at+8+length); assert.equal(crc(ios.subarray(at+4,at+8+length)),ios.readUInt32BE(at+8+length),'Invalid PNG chunk CRC'); if(type==='IDAT')idat.push(data);at+=length+12; }
  const pixels=inflateSync(Buffer.concat(idat)), width=180*scale, height=60*scale;
  assert.equal(pixels.length,height*(1+width*4));
  let visible=0, transparent=0;
  for(let y=0;y<height;y++){assert.equal(pixels[y*(1+width*4)],0);for(let x=0;x<width;x++){const alpha=pixels[y*(1+width*4)+1+x*4+3];if(alpha)visible++;else transparent++;}}
  assert.ok(visible>100&&transparent>100,'Reject blank/placeholder or opaque splash images');
}
const sb=await text('ios/Runner/Base.lproj/LaunchScreen.storyboard');
assert.match(sb,/contentMode="scaleAspectFit" image="LaunchImage"/);
assert.match(sb,/firstAttribute="width" constant="180"/);assert.match(sb,/firstAttribute="height" constant="60"/);
for(const folder of ['drawable','drawable-v21'])assert.match(await text('android/app/src/main/res/'+folder+'/launch_background.xml'),/@drawable\/hired_splash_logo/);
for(const folder of ['values','values-night']){const s=await text('android/app/src/main/res/'+folder+'/styles.xml');assert.doesNotMatch(s,/Theme\.Black/);assert.match(s,/@color\/hired_launch_background/);}
for(const folder of ['values-v31','values-night-v31'])assert.match(await text('android/app/src/main/res/'+folder+'/styles.xml'),/windowSplashScreenBackground/);
assert.match(await text('android/app/src/main/res/values/colors.xml'),/#F6F7FB/);
console.log('Native branding resources are consistent. Cold-start/device testing is still required.');
