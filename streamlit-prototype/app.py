from __future__ import annotations

import json
import os
import textwrap
import uuid
from datetime import date, datetime
from pathlib import Path

import streamlit as st
from PIL import Image, ImageOps

try:
    from openai import OpenAI
except ImportError:  # The app still runs with the local fallback generator.
    OpenAI = None


APP_TITLE = "하루결"
DATA_DIR = Path("data")
UPLOAD_DIR = DATA_DIR / "uploads"
ENTRY_DIR = DATA_DIR / "entries"
THUMB_DIR = DATA_DIR / "thumbnails"


def ensure_dirs() -> None:
    for path in (UPLOAD_DIR, ENTRY_DIR, THUMB_DIR):
        path.mkdir(parents=True, exist_ok=True)


def slug_date(target_date: date) -> str:
    return target_date.isoformat()


def entry_path(target_date: date) -> Path:
    return ENTRY_DIR / f"{slug_date(target_date)}.json"


def save_uploaded_photos(files: list, target_date: date) -> list[dict]:
    saved = []
    day_dir = UPLOAD_DIR / slug_date(target_date)
    thumb_day_dir = THUMB_DIR / slug_date(target_date)
    day_dir.mkdir(parents=True, exist_ok=True)
    thumb_day_dir.mkdir(parents=True, exist_ok=True)

    for file in files:
        suffix = Path(file.name).suffix.lower() or ".jpg"
        safe_name = f"{uuid.uuid4().hex}{suffix}"
        photo_path = day_dir / safe_name
        photo_path.write_bytes(file.getbuffer())

        thumb_path = thumb_day_dir / f"{Path(safe_name).stem}.jpg"
        with Image.open(photo_path) as image:
            image = ImageOps.exif_transpose(image)
            image.thumbnail((900, 900))
            image.convert("RGB").save(thumb_path, "JPEG", quality=88)

        saved.append(
            {
                "original_name": file.name,
                "path": str(photo_path),
                "thumbnail": str(thumb_path),
            }
        )
    return saved


def generate_prompt(
    target_date: date,
    mood: str,
    tone: str,
    schedules: str,
    memo: str,
    photos: list[dict],
) -> str:
    photo_names = "\n".join(
        f"- 사진 {index + 1}: {photo['original_name']}" for index, photo in enumerate(photos)
    )
    return textwrap.dedent(
        f"""
        날짜: {target_date.isoformat()}
        오늘의 기분: {mood}
        원하는 문체: {tone}

        오늘의 일정:
        {schedules or "입력된 일정 없음"}

        사용자의 한 줄 메모:
        {memo or "입력된 메모 없음"}

        업로드된 사진:
        {photo_names or "업로드된 사진 없음"}

        위 정보를 바탕으로 다음 JSON 형식만 출력해줘.
        {{
          "title": "짧은 다이어리 제목",
          "keywords": ["키워드1", "키워드2", "키워드3"],
          "summary": "오늘 하루를 2문장으로 요약",
          "diary": "감성적인 한국어 일기 본문. 5~8문장.",
          "closing_line": "하루를 닫는 짧은 한 줄"
        }}
        """
    ).strip()


def fallback_diary(
    target_date: date,
    mood: str,
    tone: str,
    schedules: str,
    memo: str,
    photos: list[dict],
) -> dict:
    schedule_lines = [line.strip("- ").strip() for line in schedules.splitlines() if line.strip()]
    first_schedule = schedule_lines[0] if schedule_lines else "작은 순간들"
    photo_note = f"사진 {len(photos)}장이 오늘의 분위기를 조용히 붙잡아 주었다." if photos else ""
    memo_note = f"메모로 남긴 '{memo}'라는 말이 오늘의 중심에 남았다." if memo else ""

    diary = [
        f"오늘은 {target_date.strftime('%Y년 %m월 %d일')}, 마음의 결이 {mood} 쪽으로 기울어 있던 하루였다.",
        f"{first_schedule}에서 시작된 시간은 생각보다 천천히 흘렀고, 그 안에 사소하지만 분명한 장면들이 있었다.",
    ]
    if memo_note:
        diary.append(memo_note)
    if photo_note:
        diary.append(photo_note)
    diary.extend(
        [
            "크게 특별한 일이 아니어도, 하루를 다시 바라보면 나름의 색과 온도가 있다는 걸 알게 된다.",
            "오늘의 기록은 완벽하지 않아도 충분히 나답고, 그래서 오래 남겨둘 만하다.",
        ]
    )

    return {
        "title": "오늘의 작은 결",
        "keywords": [mood, tone, "기록"],
        "summary": "오늘의 일정과 메모를 바탕으로 하루의 흐름을 정리했다. 사진과 함께 기억할 만한 장면을 다이어리로 남겼다.",
        "diary": "\n\n".join(diary),
        "closing_line": "오늘도 나의 하루는 조용히 한 페이지가 되었다.",
    }


def generate_diary(
    target_date: date,
    mood: str,
    tone: str,
    schedules: str,
    memo: str,
    photos: list[dict],
) -> tuple[dict, str]:
    api_key = os.getenv("OPENAI_API_KEY")
    model = os.getenv("OPENAI_MODEL", "gpt-4.1-mini")

    if not api_key or OpenAI is None:
        return fallback_diary(target_date, mood, tone, schedules, memo, photos), "local"

    client = OpenAI(api_key=api_key)
    prompt = generate_prompt(target_date, mood, tone, schedules, memo, photos)
    system = (
        "너는 사용자의 하루를 부드럽고 구체적으로 정리하는 한국어 감성 다이어리 에이전트다. "
        "과장하지 말고, 입력된 일정과 메모를 바탕으로 실제 있었을 법한 하루의 흐름을 만들어라."
    )

    try:
        response = client.responses.create(
            model=model,
            instructions=system,
            input=prompt,
        )
        text = response.output_text.strip()
        if text.startswith("```"):
            text = text.strip("`")
            text = text.removeprefix("json").strip()
        return json.loads(text), model
    except Exception as exc:
        result = fallback_diary(target_date, mood, tone, schedules, memo, photos)
        result["closing_line"] += f" (AI 생성 실패로 로컬 문장이 사용됨: {exc})"
        return result, "local-fallback"


def save_entry(entry: dict) -> None:
    path = entry_path(date.fromisoformat(entry["date"]))
    path.write_text(json.dumps(entry, ensure_ascii=False, indent=2), encoding="utf-8")


def load_entries() -> list[dict]:
    entries = []
    for path in sorted(ENTRY_DIR.glob("*.json"), reverse=True):
        try:
            entries.append(json.loads(path.read_text(encoding="utf-8")))
        except json.JSONDecodeError:
            continue
    return entries


def render_photo_grid(photos: list[dict]) -> None:
    if not photos:
        st.info("아직 사진이 없어요. 오늘의 장면을 몇 장 올려보세요.")
        return

    columns = st.columns(min(3, len(photos)))
    for index, photo in enumerate(photos):
        with columns[index % len(columns)]:
            st.image(photo["thumbnail"], use_container_width=True)


def render_diary_page(entry: dict) -> None:
    result = entry["result"]

    st.markdown(
        f"""
        <section class="diary-page">
            <div class="diary-date">{entry["date"]}</div>
            <h1>{result["title"]}</h1>
            <p class="summary">{result["summary"]}</p>
            <div class="keyword-row">
                {"".join(f"<span>{keyword}</span>" for keyword in result.get("keywords", []))}
            </div>
        </section>
        """,
        unsafe_allow_html=True,
    )
    render_photo_grid(entry.get("photos", []))
    st.markdown(f"<div class='diary-body'>{result['diary']}</div>", unsafe_allow_html=True)
    st.markdown(f"<p class='closing-line'>{result['closing_line']}</p>", unsafe_allow_html=True)


def inject_styles() -> None:
    st.markdown(
        """
        <style>
        :root {
            --ink: #2b2725;
            --paper: #fffaf3;
            --rose: #e9a6a1;
            --sage: #8ba888;
            --sky: #8fb6d8;
            --line: #eadfd3;
        }

        .stApp {
            background: linear-gradient(180deg, #fffaf3 0%, #f6f1e9 100%);
            color: var(--ink);
        }

        h1, h2, h3 {
            letter-spacing: 0;
        }

        .block-container {
            max-width: 1040px;
            padding-top: 2.4rem;
            padding-bottom: 4rem;
        }

        .app-title {
            display: flex;
            align-items: end;
            justify-content: space-between;
            gap: 1rem;
            border-bottom: 1px solid var(--line);
            padding-bottom: 1rem;
            margin-bottom: 1.5rem;
        }

        .app-title h1 {
            margin: 0;
            font-size: 2.7rem;
            color: var(--ink);
        }

        .app-title p {
            margin: 0;
            color: #7a7169;
        }

        .diary-page {
            background: rgba(255, 250, 243, 0.74);
            border: 1px solid var(--line);
            border-radius: 8px;
            padding: 1.25rem;
            margin: 1rem 0;
        }

        .diary-date {
            color: #8e8177;
            font-size: 0.92rem;
            margin-bottom: 0.2rem;
        }

        .diary-page h1 {
            font-size: 2rem;
            margin: 0 0 0.45rem 0;
        }

        .summary {
            color: #5e5650;
            line-height: 1.65;
            margin-bottom: 0.9rem;
        }

        .keyword-row {
            display: flex;
            flex-wrap: wrap;
            gap: 0.45rem;
        }

        .keyword-row span {
            border: 1px solid var(--line);
            border-radius: 999px;
            padding: 0.28rem 0.62rem;
            background: #fff;
            color: #5f6757;
            font-size: 0.86rem;
        }

        .diary-body {
            background: rgba(255, 255, 255, 0.62);
            border-left: 4px solid var(--rose);
            border-radius: 6px;
            line-height: 1.9;
            margin-top: 1rem;
            padding: 1rem 1.1rem;
            white-space: pre-wrap;
        }

        .closing-line {
            color: #6f655e;
            font-style: italic;
            margin-top: 1rem;
        }

        div[data-testid="stImage"] img {
            border-radius: 8px;
            border: 1px solid var(--line);
        }

        @media (max-width: 700px) {
            .app-title {
                align-items: start;
                flex-direction: column;
            }

            .app-title h1 {
                font-size: 2.2rem;
            }
        }
        </style>
        """,
        unsafe_allow_html=True,
    )


def main() -> None:
    ensure_dirs()
    st.set_page_config(page_title=APP_TITLE, page_icon="📔", layout="wide")
    inject_styles()

    st.markdown(
        """
        <div class="app-title">
            <div>
                <h1>하루결</h1>
                <p>일정, 사진, 기분을 한 페이지의 감성 다이어리로 정리합니다.</p>
            </div>
        </div>
        """,
        unsafe_allow_html=True,
    )

    write_tab, archive_tab = st.tabs(["오늘 기록", "지난 기록"])

    with write_tab:
        left, right = st.columns([0.95, 1.05], gap="large")

        with left:
            st.subheader("오늘의 재료")
            target_date = st.date_input("날짜", value=date.today())
            mood = st.selectbox(
                "기분",
                ["평온", "설렘", "뿌듯함", "지침", "아쉬움", "행복", "복잡함"],
            )
            tone = st.segmented_control(
                "문체",
                ["담백하게", "감성적으로", "귀엽게", "짧고 선명하게"],
                default="감성적으로",
            )
            schedules = st.text_area(
                "오늘 일정",
                placeholder="- 12:00 친구와 점심\n- 15:00 카페에서 작업\n- 19:00 산책",
                height=150,
            )
            memo = st.text_input("한 줄 메모", placeholder="오늘 기억하고 싶은 말")
            photos = st.file_uploader(
                "사진 업로드",
                type=["jpg", "jpeg", "png", "webp"],
                accept_multiple_files=True,
            )

            submitted = st.button("다이어리 만들기", type="primary", use_container_width=True)

        with right:
            st.subheader("미리보기")
            if submitted:
                saved_photos = save_uploaded_photos(photos or [], target_date)
                result, generator = generate_diary(
                    target_date=target_date,
                    mood=mood,
                    tone=tone or "감성적으로",
                    schedules=schedules,
                    memo=memo,
                    photos=saved_photos,
                )
                entry = {
                    "id": uuid.uuid4().hex,
                    "date": target_date.isoformat(),
                    "created_at": datetime.now().isoformat(timespec="seconds"),
                    "mood": mood,
                    "tone": tone,
                    "schedules": schedules,
                    "memo": memo,
                    "photos": saved_photos,
                    "result": result,
                    "generator": generator,
                }
                save_entry(entry)
                st.success("오늘의 다이어리를 저장했어요.")
                render_diary_page(entry)
            else:
                latest_entries = load_entries()
                if latest_entries:
                    render_diary_page(latest_entries[0])
                else:
                    st.info("왼쪽에 오늘의 재료를 넣고 첫 페이지를 만들어보세요.")

    with archive_tab:
        entries = load_entries()
        if not entries:
            st.info("저장된 기록이 아직 없어요.")
            return

        labels = [f"{entry['date']} · {entry['result']['title']}" for entry in entries]
        selected = st.selectbox("기록 선택", labels)
        render_diary_page(entries[labels.index(selected)])


if __name__ == "__main__":
    main()
