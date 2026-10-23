import { TalkingHead } from 'talkinghead';
import { HeadAudio } from './headaudio/headaudio.min.mjs';

const nodeAvatar = document.getElementById('avatar');
const veil = document.getElementById('veil');
const statusNode = document.getElementById('status');

let head = null;
let headAudio = null;
let streamActive = false;
let streamSampleRate = 16000;
let disposed = false;

function post(type, data = {}) {
  try {
    window.AvatarBridge?.postMessage(JSON.stringify({ type, ...data }));
  } catch (_) {}
}

function status(text) {
  statusNode.textContent = text;
}

function pcmFromBase64(value) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return new Int16Array(bytes.buffer, bytes.byteOffset, bytes.byteLength >> 1);
}

function customizeNurseAppearance() {
  head.armature?.traverse((object) => {
    if (!object.isMesh || !object.material) return;
    const wasArray = Array.isArray(object.material);
    const materials = wasArray ? object.material : [object.material];
    const objectName = (object.name || '').toLowerCase();
    const restyled = materials.map((source) => {
      const material = source.clone();
      const name = `${objectName} ${(material.name || '').toLowerCase()}`;
      if (name.includes('female_casualsuit')) {
        material.map = null;
        material.color?.setHex(0xdcebed);
        if ('roughness' in material) material.roughness = 0.72;
        if ('metalness' in material) material.metalness = 0.0;
      }
      if (name.includes('ponytail')) {
        material.color?.setHex(0x242628);
        if ('roughness' in material) material.roughness = 0.82;
      }
      material.needsUpdate = true;
      return material;
    });
    object.material = wasArray ? restyled : restyled[0];
  });
}

async function prepareAudioLipSync() {
  await head.audioCtx.audioWorklet.addModule('./headaudio/headworklet.min.mjs');
  headAudio = new HeadAudio(head.audioCtx, {
    processorOptions: {},
    parameterData: {
      vadMode: 1,
      vadGateActiveDb: -46,
      vadGateInactiveDb: -58,
      speakerMeanHz: 220,
    },
  });
  await headAudio.loadModel('./headaudio/model-en-mixed.bin');
  head.audioSpeechGainNode.connect(headAudio);
  headAudio.onvalue = (key, value) => {
    const target = head.mtAvatar[key];
    if (target) Object.assign(target, { newvalue: value, needsUpdate: true });
  };
  headAudio.onstarted = () => {
    head.lookAtCamera(700);
  };
  head.opt.update = headAudio.update.bind(headAudio);
}

async function initialize() {
  try {
    head = new TalkingHead(nodeAvatar, {
      modelFPS: 30,
      modelPixelRatio: 1,
      lipsyncModules: [],
      cameraView: 'upper',
      cameraRotateEnable: false,
      cameraPanEnable: false,
      cameraZoomEnable: false,
      avatarIdleEyeContact: 1.0,
      avatarIdleHeadMove: 0.0,
      avatarSpeakingEyeContact: 0.96,
      avatarSpeakingHeadMove: 0.05,
      avatarIgnoreCamera: true,
      lightAmbientColor: 0xffffff,
      lightAmbientIntensity: 1.15,
      lightDirectColor: 0xfff7f2,
      lightDirectIntensity: 1.8,
      lightDirectPhi: 0.65,
      lightDirectTheta: 1.25,
    });

    await head.showAvatar(
      {
        url: './nurse_base_cc0.glb',
        body: 'F',
        avatarMood: 'neutral',
        avatarIdleEyeContact: 1.0,
        avatarSpeakingEyeContact: 0.96,
        avatarSpeakingHeadMove: 0.05,
        avatarIgnoreCamera: true,
        baseline: {
          headRotateX: -0.01,
          eyeBlinkLeft: 0.05,
          eyeBlinkRight: 0.05,
          mouthSmileLeft: 0.06,
          mouthSmileRight: 0.06,
        },
        modelDynamicBones: [
          { bone: 'Ponytail1', type: 'mix2', stiffness: 120, damping: 5, limits: [null, null, [null, 0.015], null], pivot: true },
          { bone: 'Ponytail2', type: 'mix2', stiffness: 170, damping: 5, limits: [null, null, [null, 0.008], null] },
          { bone: 'Ponytail3', type: 'mix2', stiffness: 220, damping: 5, limits: [null, null, [null, 0.008], null] },
        ],
      },
      (url, progress) => {
        if (progress?.lengthComputable && progress.total > 0) {
          status(`正在加载本地3D护士 ${Math.round(progress.loaded * 100 / progress.total)}%`);
        }
      },
    );

    customizeNurseAppearance();
    head.renderer.toneMappingExposure = 0.78;
    head.setView('upper', { cameraDistance: -0.18, cameraY: 0.035 });
    await prepareAudioLipSync();
    head.audioCtx.resume().catch(() => {});
    head.lookAhead(60000);
    veil.classList.add('hidden');
    post('ready');
  } catch (error) {
    console.error(error);
    status('3D形象加载失败，已切换原真人形象');
    post('error', { message: String(error?.message || error) });
  }
}

async function ensureStream(sampleRate) {
  if (!head || !headAudio) throw new Error('3D avatar is not ready');
  await head.audioCtx.resume();
  if (streamActive && streamSampleRate === sampleRate) return;
  if (streamActive) await head.streamStop();
  streamSampleRate = sampleRate;
  await head.streamStart({
    sampleRate,
    gain: 1,
    waitForAudioChunks: true,
    lipsyncType: 'visemes',
  });
  streamActive = true;
}

window.digitalNurseStartStream = async (sampleRate) => {
  await ensureStream(Number(sampleRate) || 16000);
};

window.digitalNursePushPcm = async (base64) => {
  if (!streamActive) await ensureStream(streamSampleRate);
  head.streamAudio({ audio: pcmFromBase64(base64) });
};

window.digitalNurseEndStream = async () => {
  if (!streamActive || !head) return;
  head.streamNotifyEnd();
  streamActive = false;
};

window.digitalNurseInterrupt = async () => {
  if (!head) return;
  if (streamActive) head.streamInterrupt();
  streamActive = false;
};

window.digitalNurseSetState = (state, emotion = 'neutral') => {
  if (!head) return;
  const mood = ['happy', 'sad', 'angry', 'fear', 'disgust', 'love'].includes(emotion)
    ? emotion
    : state === 'warning' ? 'fear' : 'neutral';
  head.setMood(mood);
  if (state === 'idle' || state === 'connecting') head.lookAhead(60000);
  if (state === 'listening') head.makeEyeContact(1200);
  if (state === 'speaking') head.lookAhead(900);
  if (state === 'thinking') head.lookAhead(650);
};

window.addEventListener('pagehide', () => {
  if (disposed) return;
  disposed = true;
  head?.dispose?.();
});

initialize();
