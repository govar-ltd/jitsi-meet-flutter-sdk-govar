/// Text follows Govar's selected UI language, independent of device locale.
class GovarCallNotification {
  static List<String> forLanguage(String language) {
    final code = language.toLowerCase().replaceAll('-', '_').split('_').first;
    return translations[code] ?? translations['en']!;
  }

  static const translations = <String, List<String>>{
    "en": ["Govar — meeting in progress", "Microphone is used for the conversation"],
    "ru": ["Govar — идёт встреча", "Микрофон используется для разговора"],
    "ar": ["Govar — اجتماع جارٍ", "يُستخدم الميكروفون للمحادثة"],
    "es": ["Govar — reunión en curso", "El micrófono se usa para la conversación"],
    "kk": ["Govar — кездесу өтіп жатыр", "Микрофон сөйлесу үшін қолданылуда"],
    "fr": ["Govar — réunion en cours", "Le microphone est utilisé pour la conversation"],
    "it": ["Govar — incontro in corso", "Il microfono è utilizzato per la conversazione"],
    "ms": ["Govar — sesi sedang berlangsung", "Mikrofon digunakan untuk perbualan"],
    "hi": ["Govar — मीटिंग जारी है", "बातचीत के लिए माइक्रोफ़ोन का उपयोग हो रहा है"],
    "ur": ["Govar — میٹنگ جاری ہے", "گفتگو کے لیے مائیکروفون استعمال ہو رہا ہے"],
    "de": ["Govar — Treffen läuft", "Das Mikrofon wird für das Gespräch verwendet"],
    "id": ["Govar — pertemuan berlangsung", "Mikrofon digunakan untuk percakapan"],
    "pt": ["Govar — encontro em andamento", "O microfone está a ser usado para a conversa"],
    "uk": ["Govar — триває зустріч", "Мікрофон використовується для розмови"],
    "zh": ["Govar — 会议进行中", "麦克风正用于通话"],
    "fa": ["Govar — جلسه در حال برگزاری است", "میکروفون برای مکالمه استفاده می‌شود"],
    "tr": ["Govar — görüşme sürüyor", "Mikrofon konuşma için kullanılıyor"],
    "am": ["Govar — ስብሰባ በሂደት ላይ ነው", "ማይክሮፎኑ ለውይይቱ እየተጠቀመ ነው"],
    "vi": ["Govar — cuộc gặp đang diễn ra", "Micrô đang được dùng cho cuộc trò chuyện"],
    "ne": ["Govar — बैठक जारी छ", "कुराकानीका लागि माइक्रोफोन प्रयोग भइरहेको छ"],
    "uz": ["Govar — uchrashuv davom etmoqda", "Mikrofon suhbat uchun ishlatilmoqda"],
    "bn": ["Govar — মিটিং চলছে", "কথোপকথনের জন্য মাইক্রোফোন ব্যবহার করা হচ্ছে"],
    "pl": ["Govar — spotkanie trwa", "Mikrofon jest używany do rozmowy"],
    "be": ["Govar — ідзе сустрэча", "Мікрафон выкарыстоўваецца для размовы"],
    "ro": ["Govar — întâlnire în desfășurare", "Microfonul este folosit pentru conversație"],
    "hy": ["Govar — հանդիպումն ընթացքի մեջ է", "Խոսակցության համար օգտագործվում է խոսափողը"],
    "cs": ["Govar — probíhá setkání", "Mikrofon se používá pro konverzaci"],
    "tg": ["Govar — вохӯрӣ идома дорад", "Микрофон барои суҳбат истифода мешавад"],
    "ko": ["Govar — 모임 진행 중", "대화를 위해 마이크를 사용하고 있습니다"],
    "ka": ["Govar — შეხვედრა მიმდინარეობს", "მიკროფონი საუბრისთვის გამოიყენება"],
    "hu": ["Govar — találkozó folyamatban", "A mikrofon használatban van a beszélgetéshez"],
    "ja": ["Govar — ミーティング中", "会話のためにマイクを使用しています"],
    "bg": ["Govar — срещата е в ход", "Микрофонът се използва за разговора"],
    "sv": ["Govar — möte pågår", "Mikrofonen används för samtalet"],
    "he": ["Govar — מפגש מתקיים", "המיקרופון משמש לשיחה"],
    "fi": ["Govar — tapaaminen käynnissä", "Mikrofonia käytetään keskusteluun"],
    "sk": ["Govar — prebieha stretnutie", "Mikrofón sa používa na rozhovor"],
    "el": ["Govar — συνάντηση σε εξέλιξη", "Το μικρόφωνο χρησιμοποιείται για τη συνομιλία"],
  };
}
