# JavaFX Game Show Quiz

## Project Overview

This JavaFX application delivers an interactive geography quiz, dynamically loading questions from a CSV dataset and tracking user performance. It demonstrates object‑oriented design, event‑driven UI, multithreading, file I/O, and integration with JavaFX.

## Prerequisites

- Java 11 or higher (with JavaFX support)
- Maven 3.6+ for build and dependency management

## Directory Structure

```
javafx_game_show_quiz/
├── pom.xml
├── README.md
├── src/
│   ├── main/
│   │   ├── java/edu/uga/cs1302/quiz/
│   │   │   ├── Country.java
│   │   │   ├── CountryCollection.java
│   │   │   ├── GeographyQuiz.java
│   │   │   ├── Question.java
│   │   │   ├── Quiz.java
│   │   │   ├── QuizResult.java
│   │   │   └── QuizScore.java
│   │   └── resources/
│   │       └── country_continent.csv
│   └── test/
│       └── java/edu/uga/cs1302/quiz/
│           └── TestCountryCollection.java
└── .gitignore
```

## Build Instructions

From the project root, run:

```bash
mvn compile
```

## Running the Application

Use the Maven Exec plugin:

```bash
mvn exec:java -Dexec.mainClass="edu.uga.cs1302.quiz.GeographyQuiz"
```

## Data & Examples

- `src/main/resources/country_continent.csv`: Source data for quiz questions.
- Sample quiz outputs are written to `quiz_results.dat` at runtime.

## Git Ignore

Ensure generated files and folders are excluded by adding:

```gitignore
/target/
**/*.class
maven-status/
```

## Author

Dawson Gulasa
