.PHONY: build run app list clean

build:
	swift build -c release

run: build
	.build/release/PaperWindow

list: build
	.build/release/PaperWindow --list

app:
	./Scripts/make-app.sh

clean:
	rm -rf .build build
