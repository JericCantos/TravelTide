# TravelTide
Customer Segmentation of a Travel e-Booking Site

## data
To connect to the database containing the Travel Tide data, refer to the connection string under `data/raw`.

We are given transactional data across four tables:
1. users: contains user demographic information (e.g. birthdate, gender, marital status)
2. sessions: main transaction table containing infoormation on user activities (e.g. did they book? how many clicks? how long?)
3. flights: contains info about purchased flights (e.g. origin and destination, checked bags, base fare)
4. hotels: contains info about booked hotels (e.g. hotel chain and location, check-in and check-out time, room rate)

I have exported the raw session-level aggregation as well as the cleaned user-level aggregation as csv files. They can be found under `data/processed`


## Outputs
- The users of each traditionally-defined persona have been isolated and their details extracted in separate csv files.
- The users who were not addressed by these personas were clustered using KMeans, and the entire dataset with groupings have been exported to its own file (`df_unaddressed_users_clustered.csv`)