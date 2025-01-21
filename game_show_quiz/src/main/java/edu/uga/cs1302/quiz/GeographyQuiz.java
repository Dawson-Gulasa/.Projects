package edu.uga.cs1302.quiz;

import javafx.animation.PauseTransition;
import javafx.application.Application;
import javafx.scene.Scene;
import javafx.scene.control.*;
import javafx.scene.layout.VBox;
import javafx.stage.Modality;
import javafx.stage.Stage;
import javafx.util.Duration;

public class GeographyQuiz extends Application
{
    private CountryCollection countryCollection;
    private QuizResult quizResult;

    // sets up the primary window
    @Override
    public void start(Stage primaryStage)
    {
	primaryStage.setTitle("Geography Quiz");
	
	// Load country data reading from the csv file path
	countryCollection = new CountryCollection();
	try
	    {
		countryCollection.readFromCSV("/home/myid/djg58388/cs1302/project5/src/main/resources/country_continent.csv");
	    }catch(Exception e)
	    {
		e.printStackTrace();
	    }
	// Load past quiz results
	quizResult = new QuizResult();
	quizResult.loadFromFile("quiz_results.dat");

	//main menu buttons
	Button startQuizButton = new Button("Start Quiz");
	Button viewResultsButton = new Button("View Results");
	Button helpButton = new Button("Help");
	Button quitButton = new Button("Quit");

	startQuizButton.setOnAction(e -> startQuiz());
	viewResultsButton.setOnAction(e -> viewResults());
	helpButton.setOnAction(e -> showHelp());
	quitButton.setOnAction(e -> primaryStage.close());

	// sets the windows parameters
	VBox layout = new VBox(10);
	layout.getChildren().addAll(startQuizButton, viewResultsButton, helpButton, quitButton);
	

	Scene scene = new Scene(layout, 300, 200);
	primaryStage.setScene(scene);
	primaryStage.show();
    }

    // When start quiz button is activated, opens new window and calls on showQuestion method
    private void startQuiz()
    {
	
	Stage quizStage = new Stage();
	quizStage.initModality(Modality.APPLICATION_MODAL);
	quizStage.setTitle("Geography Quiz - New Quiz");


	Quiz quiz = new Quiz(countryCollection);
	showQuestion(quizStage, quiz, 0);
	  
	quizStage.showAndWait();
    }

    // Creates the window where questions are asked and answer choices are given using radio buttons
    private void showQuestion(Stage quizStage, Quiz quiz, int questionIndex)
    {
	VBox layout = new VBox(10);
	
	if(questionIndex < quiz.getQuestions().size())
	    {
		Question question = quiz.getQuestions().get(questionIndex);

		Label questionLabel = new Label("On which continent is " + question.getCountry().getName() + " located?");
		layout.getChildren().add(questionLabel);

		ToggleGroup choicesGroup = new ToggleGroup();
		for(String choice : question.getChoices())
		    {
			RadioButton choiceButton = new RadioButton(choice);
			choiceButton.setToggleGroup(choicesGroup);
			layout.getChildren().add(choiceButton);
		    }

		Button submitButton = new Button("Submit");
		Label feedbackLabel = new Label();
		layout.getChildren().addAll(submitButton, feedbackLabel);

		submitButton.setOnAction(e ->
					 {
					     RadioButton selectedButton = (RadioButton) choicesGroup.getSelectedToggle();
					     if(selectedButton != null)
						 {
						     String selectedChoice = selectedButton.getText();
						     if(selectedChoice.equals(question.getCountry().getContinent()))
							 {
							     quiz.incrementScore();
							     feedbackLabel.setText("Correct!");
							 }else
							 {
							     feedbackLabel.setText("Incorrect! Correct answer is " + question.getCountry().getContinent());
							  }
								 PauseTransition pause = new PauseTransition(Duration.seconds(3));
							     pause.setOnFinished(event -> showQuestion(quizStage, quiz, questionIndex + 1));
							     pause.play();
							 }
						 });
							     
		Scene scene = new Scene(layout, 300, 270);
		quizStage.setScene(scene);
		    }else
	    {
		showQuizResult(quizStage, quiz);
	    }
    }

    // Shows final quiz result at end of quiz, and stores that data in quiz_results.dat
    private void showQuizResult(Stage quizStage, Quiz quiz)
    {	
	VBox layout = new VBox(10);
	Label resultLabel = new Label("Your score is: " + quiz.getScore() + " out of 6.");
	Button closeButton = new Button("Close");
	closeButton.setOnAction(e ->
				{
				    quizResult.addResult(new QuizScore(new java.util.Date(), quiz.getScore()));
				    quizResult.saveToFile("quiz_results.dat");
				    quizStage.close();
				}
				);

	layout.getChildren().addAll(resultLabel, closeButton);

	Scene scene = new Scene(layout, 300, 200);
	quizStage.setScene(scene);
    }

    // Shows all previous attempts with dates
    private void viewResults()
    {	
	Stage resultsStage = new Stage();
	resultsStage.initModality(Modality.APPLICATION_MODAL);
	resultsStage.setTitle("Geography Quiz - Past Results");

	VBox layout = new VBox(10);
	TextArea resultsArea = new TextArea();
	resultsArea.setEditable(false);
	resultsArea.setText(quizResult.toString());

	Button closeButton = new Button("Close");
	closeButton.setOnAction(e -> resultsStage.close());

	layout.getChildren().addAll(resultsArea, closeButton);

	Scene scene = new Scene(layout, 500, 370);
	resultsStage.setScene(scene);
	resultsStage.showAndWait();
    }

    // shows a window with the explanation of how to work through the quiz
    private void showHelp()
    {
	Stage helpStage = new Stage();
	helpStage.initModality(Modality.APPLICATION_MODAL);
	helpStage.setTitle("Geography Quiz - Help");

	VBox layout = new VBox(10);
	Label helpLabel = new Label("Welcome to the Geography Quiz!\n\n"
				    + "This quiz will test your knowledge of countries and their continents.\n"
				    + "You will be asked about the continent of six randomly selected countries.\n"
				    + "Select the correct continent to score points.\n"
				    + "Good Luck!");

	Button closeButton = new Button("Close");
	closeButton.setOnAction(e -> helpStage.close());

	layout.getChildren().addAll(helpLabel, closeButton);

	Scene scene = new Scene(layout, 500, 350);
	helpStage.setScene(scene);
	helpStage.showAndWait();
    }

    // begins the program
    public static void main(String[] args)
    {
	launch(args);
    }
}
