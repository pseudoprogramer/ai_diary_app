# 하루결

일정, 사진, 기분, 한 줄 메모를 바탕으로 하루를 감성 다이어리 페이지로 정리하는 개인용 AI 다이어리 프로토타입입니다.

## 기능

- 오늘 일정과 기분 입력
- 사진 여러 장 업로드
- AI 기반 감성 일기 생성
- API 키가 없어도 로컬 fallback 문장으로 실행
- 날짜별 기록 저장 및 다시 보기

## 실행

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
streamlit run app.py
```

OpenAI API로 일기를 생성하려면 실행 전에 환경 변수를 설정하세요.

```powershell
$env:OPENAI_API_KEY="your_api_key"
```

모델을 바꾸고 싶으면 다음 환경 변수를 사용할 수 있습니다.

```powershell
$env:OPENAI_MODEL="gpt-4.1-mini"
```

## 데이터 저장

앱에서 만든 기록과 업로드 이미지는 `data/` 폴더에 저장됩니다. 개인 기록이므로 기본적으로 Git 백업 대상에서 제외됩니다.
