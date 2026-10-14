# GeoEngine Backend

[English](README.md)

GeoEngine bir fotoğrafın nerede çekildiğini tahmin etmeye çalışıyor. Fikir OSINT çalışmalarından geliyor: görselde GPS bilgisi yoksa analist tabelalara, binalara, bitki örtüsüne bakıp konumu adım adım daraltır. GeoEngine bu işin küçük bir kısmını, birbirinden bağımsız birkaç tahmini birleştirerek otomatikleştiriyor.

Erken aşama bir kavram kanıtı (PoC), bitmiş bir araç değil. Bu repoda FastAPI backend'i ve bir Flutter istemcisi (`app/`) var. Proje önerisi ve literatür taraması [GeoEngine-web](https://github.com/Runomm/GeoEngine-web) reposunda.

## Nasıl çalışıyor

`POST /analyze` bir görsel alıp dört adımı sırayla çalıştırıyor:

1. **OCR:** Tesseract görseldeki yazıları okuyor.
2. **Gemini:** Görsel, fotoğrafın hangi ülkelerde çekilmiş olabileceğini soran bir prompt ile Gemini'ye gidiyor (varsayılan model `gemini-3.8-flash`). Cevap yapılandırılmış JSON olarak dönüyor: her aday için İngilizce ad, ISO 3166-1 alpha-3 kodu ve kısa bir gerekçe. `GEMINI_API_KEY` tanımlı değilse bu adım atlanıyor. Çağrı başarısız olursa istek Gemini olmadan devam ediyor ve hata `cognitive_error` alanında dönüyor.
3. **PLONK:** `nicolas-dufour/PLONK_YFCC` modeli görselden enlem ve boylam tahmin ediyor. GPU varsa onu kullanıyor; VRAM boşalsın diye model her istekten sonra bellekten atılıyor.
4. **Kesişim:** GeoPandas ve Shapely ile PLONK'un verdiği noktanın Gemini'nin önerdiği ülkelerden birinin içinde kalıp kalmadığına bakılıyor. Ülkeler, Natural Earth 1:110m sınırlarıyla ISO kodu ya da adı üzerinden eşleştiriliyor. Nokta bunlardan birinin içindeyse güven `high`, değilse `low`.

Yanıtta her adımın ham çıktısı ve birleşik sonuç birlikte dönüyor:

```json
{
  "status": "success",
  "filename": "photo.jpg",
  "ocr_extracted_text": "...",
  "cognitive_analysis": "...",
  "cognitive_error": null,
  "plonk_spatial_distribution": { "type": "Feature", "geometry": { "type": "Point", "coordinates": [2.35, 48.85] } },
  "results": {
    "latitude": 48.85,
    "longitude": 2.35,
    "confidence": "high",
    "intersecting_countries": ["France"],
    "cognitive_candidates": ["France", "Belgium"]
  }
}
```

## Backend'i çalıştırma

Python 3, sistemde kurulu [Tesseract](https://github.com/tesseract-ocr/tesseract) (`pytesseract` sadece onu çağırıyor) ve mümkünse bir NVIDIA GPU gerekiyor. PLONK CPU'da da çalışıyor, sadece yavaş.

```bash
pip install -r requirements.txt
python main.py
```

Sunucu 8000 portunda açılıyor; FastAPI'nin etkileşimli dokümanı `http://localhost:8000/docs` adresinde. Gemini adımını açmak için başlatmadan önce `GEMINI_API_KEY` ortam değişkenini tanımla. Başka bir model kullanmak istersen `GEMINI_MODEL` ile değiştirebilirsin.

İnternet bağlantısı gerekiyor: PLONK ağırlıkları ilk istekte Hugging Face'ten iniyor, ülke sınırları da her istekte yeniden indiriliyor.

## Flutter istemcisi

`app/` küçük bir Flutter istemcisi. Bir fotoğraf seçip `/analyze`'a gönderiyorsun; tahmin edilen nokta OpenStreetMap haritasında, ham JSON da altında görünüyor.

```bash
cd app
flutter pub get
flutter run
```

Backend adresi `app/lib/main.dart` içinde sabit yazılı: web ve masaüstünde `localhost:8000`, Android emülatöründe `10.0.2.2:8000`. Backend her kaynaktan gelen isteği kabul ettiği için web derlemesi (`flutter run -d chrome`) de ona ulaşabiliyor.

## Bilinen sorunlar

- PLONK her istekte yeniden yükleniyor ve sınır dosyası her seferinde tekrar iniyor; bu yüzden her istek yavaş.
- 1:110m sınırlar kaba. Kıyıya ya da sınıra yakın bir nokta doğru ülkenin hemen dışına düşebiliyor; çok küçük ülkeler ise veri setinde hiç yok.
- Öneride EXIF okuma, gölge ve güneş açısı analizi ile React/Leaflet web istemcisi de planlanmıştı. Bunların hiçbiri yapılmadı.

## Klasör yapısı

```
main.py                            FastAPI uygulaması ve /analyze endpoint'i
ai_agents/ocr_agent.py             Tesseract OCR
ai_agents/cognitive_agent.py       Gemini prompt'u
psdm_engine/plonk_runner.py        PLONK çıkarımı
psdm_engine/intersection_logic.py  nokta-ülke kontrolü
app/                               Flutter istemcisi
```

## İlgili repolar

- [GeoEngine-web](https://github.com/Runomm/GeoEngine-web): proje önerisi, literatür taraması, sunum
- [GeoEngine-app](https://github.com/Runomm/GeoEngine-app): ilk ve en basit istemci
