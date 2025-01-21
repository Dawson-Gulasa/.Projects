package edu.uga.cs1302.quiz;

public class TestCountryCollection
{
    public static void main(String[] args)
    {
	CountryCollection countryCollection = new CountryCollection();

	try
	    {
		countryCollection.readFromCSV("src/main/resources/country_continent.csv");
		Quiz quiz = new Quiz(countryCollection);
		System.out.println(quiz);
	    }catch(Exception e)
	    {
		e.printStackTrace();
	    }
    }
}
