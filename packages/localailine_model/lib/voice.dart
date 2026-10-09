
enum EnginePart { redis, livekit, sip, bridge, gateway, whisper, accurate, agent }

enum PartState { missing, stopped, starting, running, failed }

/// Languages the live voice understands and speaks (code → label).
const voiceLanguages = {
  'auto': 'Detect automatically',
  'en': 'English',
  'fa': 'Persian (فارسی)',
  'ar': 'Arabic',
  'de': 'German',
  'es': 'Spanish',
  'fr': 'French',
  'it': 'Italian',
  'nl': 'Dutch',
  'pt': 'Portuguese',
  'ru': 'Russian',
  'tr': 'Turkish',
  'zh': 'Chinese',
};

/// Voices per language (Piper, downloaded on first use). The first is the default.
const voiceOptions = <String, Map<String, String>>{
  'en': {
    'kokoro:af_heart': 'Heart · natural, American, female',
    'kokoro:af_bella': 'Bella · natural, American, female',
    'kokoro:af_nicole': 'Nicole · natural, American, soft',
    'kokoro:am_michael': 'Michael · natural, American, male',
    'kokoro:am_fenrir': 'Fenrir · natural, American, male',
    'kokoro:bf_emma': 'Emma · natural, British, female',
    'kokoro:bf_isabella': 'Isabella · natural, British, female',
    'kokoro:bm_george': 'George · natural, British, male',
    'kokoro:bm_fable': 'Fable · natural, British, male',
    'en_GB-alba-medium': 'Alba · standard, British, female',
    'en_US-ryan-medium': 'Ryan · standard, American, male',
  },
  'es': {'kokoro:ef_dora': 'Dora · natural, female', 'kokoro:em_alex': 'Alex · natural, male', 'es_ES-davefx-medium': 'Dave · standard, male'},
  'fr': {'kokoro:ff_siwis': 'Siwis · natural, female', 'fr_FR-tom-medium': 'Tom · standard, male'},
  'it': {'kokoro:if_sara': 'Sara · natural, female', 'kokoro:im_nicola': 'Nicola · natural, male'},
  'pt': {'kokoro:pf_dora': 'Dora · natural, female', 'kokoro:pm_alex': 'Alex · natural, male'},
  'zh': {'kokoro:zf_xiaoxiao': 'Xiaoxiao · natural, female', 'kokoro:zm_yunxi': 'Yunxi · natural, male'},
  'fa': {'fa_IR-gyro-medium': 'Gyro · clearest', 'fa_IR-ganji_adabi-medium': 'Ganji (literary)', 'fa_IR-mana-medium': 'Mana · female', 'fa_IR-reza_ibrahim-medium': 'Reza', 'fa_IR-amir-medium': 'Amir'},
  'ar': {'ar_JO-kareem-medium': 'Kareem · male'},
  'de': {'de_DE-thorsten-medium': 'Thorsten · male', 'de_DE-kerstin-low': 'Kerstin · female'},
};

const soundOptions = {'keyboard': 'Typing', 'keyboard2': 'Soft typing', 'office': 'Office', 'hold': 'Hold music', 'none': 'Silence'};

const ambientOptions = {'none': 'None', 'office': 'Office', 'room': 'Busy room', 'city': 'City', 'forest': 'Forest'};

/// Settings for a landline gateway box (FXO), to type into the box: it forwards the line's calls
/// to the SIP server at [lanIp]:[sipPort].
List<(String, String)> landlineGatewaySettings(Map<String, dynamic> cfg, String? lanIp, int sipPort) => [
      ('SIP server (primary)', '${lanIp ?? 'this computer’s IP address'}:$sipPort'),
      ('Transport', 'UDP'),
      ('SIP user ID and Authenticate ID', '${cfg['sipUser']}'),
      ('Authenticate password', '${cfg['sipPass']}'),
      ('Incoming calls from the phone line (PSTN → VoIP)', 'Forward every call to the SIP server, answering after one ring (often "Unconditional call forward to VoIP" or "Stage method: 1")'),
      ('Caller ID', 'Turn on caller ID detection, so the assistant knows who is calling'),
    ];
