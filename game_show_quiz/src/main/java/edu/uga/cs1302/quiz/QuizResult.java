package edu.uga.cs1302.quiz;

import java.io.*;
import java.util.ArrayList;
import java.util.List;

public class QuizResult implements Serializable
{
    private List<QuizScore> results;

    public QuizResult()
    {
	this.results = new ArrayList<>();
    }

    public void addResult(QuizScore result)
    {
	results.add(0, result);
    }

    // stores the quiz results
    public void saveToFile(String filepath)
    {
	try(ObjectOutputStream oos = new ObjectOutputStream(new FileOutputStream(filepath)))
	    {
		oos.writeObject(this);
	    }catch(IOException e)
	    {
		e.printStackTrace();
	    }
    }

    // loads previous quiz results
    public void loadFromFile(String filepath)
    {
	File file = new File(filepath);
	if(file.exists())
	    {
		try(ObjectInputStream ois = new ObjectInputStream(new FileInputStream(filepath)))
		    {
			QuizResult loaded = (QuizResult) ois.readObject();
			this.results = loaded.results;
		    }catch(IOException | ClassNotFoundException e)
		    {
			e.printStackTrace();
		    }
	    }
    }

    // override of the toString method
    @Override
    public String toString()
    {
	StringBuilder sb = new StringBuilder();
	for(QuizScore score : results)
	    {
		sb.append(score.toString()).append("\n");
	    }
	return sb.toString();
    }
}
