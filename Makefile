# Blog 포스트 도구

DATE := $(shell date +%Y-%m-%d)

.PHONY: new-post serve build

## 새 포스트 생성
## 사용법: make new-post slug="lending-protocol-day-1" title="Lending Protocol - Day 1: 기본 개념"
## 옵션:
##   slug     - 파일명 (필수, 예: lending-protocol-day-1)
##   title    - 포스트 제목 (필수)
##   tags     - 태그 (선택, 예: tags='"DeFi", "Lending"')
##   categories - 카테고리 (선택, 예: categories='"DeFi"')
##   series   - 시리즈 (선택, 예: series='"Lending Protocol 스터디"')
##   desc     - 설명 (선택)
##   template - 아키타입 파일 (선택, 기본: default)
new-post:
ifndef slug
	$(error slug은 필수입니다. 사용법: make new-post slug="my-post" title="제목")
endif
ifndef title
	$(error title은 필수입니다. 사용법: make new-post slug="my-post" title="제목")
endif
	$(eval TEMPLATE := $(or $(template),default))
	$(eval TAGS := $(or $(tags),))
	$(eval CATEGORIES := $(or $(categories),))
	$(eval SERIES := $(or $(series),))
	$(eval DESC := $(or $(desc),))
	@FILE="content/post/$(slug).md"; \
	if [ -f "$$FILE" ]; then \
		echo "ERROR: $$FILE 이미 존재합니다."; \
		exit 1; \
	fi; \
	sed -e 's|{{ .title }}|$(title)|g' \
	    -e 's|{{ .date }}|$(DATE)|g' \
	    -e 's|{{ .description }}|$(DESC)|g' \
	    -e 's|{{ .tags }}|$(TAGS)|g' \
	    -e 's|{{ .categories }}|$(CATEGORIES)|g' \
	    -e 's|{{ .series }}|$(SERIES)|g' \
	    archetypes/$(TEMPLATE).md > "$$FILE"; \
	echo "Created: $$FILE"

## Hugo 로컬 개발 서버 실행
serve:
	hugo server -D

## Hugo 사이트 빌드
build:
	hugo --minify
