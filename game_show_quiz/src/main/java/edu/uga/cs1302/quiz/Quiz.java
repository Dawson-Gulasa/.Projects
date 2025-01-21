package edu.uga.cs1302.quiz;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Random;

public class Quiz
{
    private List<Question> questions;
    private int score;

    public Quiz(CountryCollection countryCollection)
    {
	this.questions = new ArrayList<>();
	this.score = 0;

	// debugging statement
	if(countryCollection.size() < 6)
	    {
		throw new IllegalArgumentException("Not enough countries to generate a quiz");
	    }

	Random random = new Random();
	List<Integer> selectedIndexes = new ArrayList<>();
	while(selectedIndexes.size() < 6)
	    {
		int randomIndex = random.nextInt(countryCollection.size());
		if(!selectedIndexes.contains(randomIndex))
		    {
			selectedIndexes.add(randomIndex);
		    }
	    }

	// the different continent choices
	List<String> continents = List.of("Africa", "Asia", "Europe", "North America", "Oceania", "South America");

	for(int index : selectedIndexes)
	    {
		Country country = countryCollection.getCountry(index);
		questions.add(new Question(country, continents));
	    }
    }

    public List<Question> getQuestions()
    {
	return questions;
    }

    // called on if question was answered correctly
    public void incrementScore()
    {
	score++;
    }

    //returns overall score
    public int getScore()
    {
	return score;
    }

    //Override of toString method
    @Override
    public String toString()
    {
	StringBuilder sb = new StringBuilder();
	for(Question question : questions)
	    {
		sb.append(question).append("\n");
	    }
	sb.append("Score: ").append(score);
	return sb.toString();
    }
}
