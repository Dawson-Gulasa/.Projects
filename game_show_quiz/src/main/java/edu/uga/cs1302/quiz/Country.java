package edu.uga.cs1302.quiz;

public class Country
{
    private String name;
    private String continent;

    public Country(String name, String continent)
    {
	this.name = name;
	this.continent = continent;
    }

    // returns the country name
    public String getName()
    {
	return name;
    }

    // returns the continent name
    public String getContinent()
    {
	return continent;
    }

    // Override of the toString method
    @Override
    public String toString()
    {
	return name + " (" + continent + ")";
    }
}
    
