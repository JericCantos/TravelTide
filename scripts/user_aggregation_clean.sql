-- fill in nulls
-- add flags
-- added days since last booking

WITH sessions_2023 AS (
    SELECT *
    FROM sessions s
    WHERE s.session_start > '2023-01-04'
),
cohort AS (
    SELECT user_id, COUNT(*) AS session_count
    FROM sessions_2023
    GROUP BY user_id
    HAVING COUNT(*) > 7
),
home_airports AS (
    SELECT DISTINCT home_airport, home_airport_lat, home_airport_lon
    FROM users
),
cancelled_trips AS (
		SELECT DISTINCT trip_id
  	FROM sessions_2023
  	WHERE cancellation = true
),
booked_trips AS (
  SELECT DISTINCT trip_id
  , flight_booked
  , hotel_booked
  FROM sessions_2023
  WHERE (flight_booked OR hotel_booked) AND NOT cancellation
),
session_aggregate_stage1 AS (
    SELECT
        s.session_id,
        s.user_id,
        s.trip_id,
        s.session_start,
        s.session_end,
        s.flight_discount,
        s.hotel_discount,
        s.flight_discount_amount,
        s.hotel_discount_amount,
        COALESCE(bt.flight_booked, s.flight_booked) as flight_booked, -- use the booking session as the basis to avoid inconsistency of "flags flipping" without corresponding hotel/flight data
        COALESCE(bt.hotel_booked, s.hotel_booked) as hotel_booked, -- use the booking session as the basis to avoid inconsistency of "flags flipping" without corresponding hotel/flight data
        s.page_clicks,
        s.cancellation,
        EXTRACT(EPOCH FROM (s.session_end - s.session_start)) AS session_duration_in_seconds,
        CASE WHEN ((COALESCE(bt.flight_booked, s.flight_booked) OR COALESCE(bt.hotel_booked, s.hotel_booked)) AND NOT cancellation) THEN session_start END AS booking_session_date,
        CASE WHEN cancellation THEN session_start END AS cancellation_session_date,
        CASE
            WHEN (COALESCE(bt.flight_booked, s.flight_booked) OR COALESCE(bt.hotel_booked, s.hotel_booked)) THEN
                CASE WHEN COALESCE(departure_time, '3000-01-01') < COALESCE(check_in_time, '3000-01-01')
                     THEN COALESCE(departure_time, '3000-01-01')
                     ELSE COALESCE(check_in_time, '3000-01-01')
                END
        END AS trip_start_date,
  			CASE WHEN ct.trip_id is not null THEN TRUE
  					 WHEN s.trip_id is null THEN null
						 ELSE FALSE
  			END AS trip_is_cancelled,
        u.birthdate,
        EXTRACT(YEAR FROM AGE('2023-07-28', u.birthdate)) AS age_in_years,
        u.gender,
        u.married,
        u.has_children,
        u.home_country,
        u.home_city,
        u.home_airport,
        u.home_airport_lat,
        u.home_airport_lon,
        u.sign_up_date,
        ('2023-07-28'::date - u.sign_up_date::date) AS days_as_customer,
        h.hotel_name,
        TRIM(SPLIT_PART(h.hotel_name, ' - ', 1)) AS hotel_chain,
        TRIM(SPLIT_PART(h.hotel_name, ' - ', 2)) AS hotel_location,
        (h.check_out_time::date - h.check_in_time::date) AS stay_in_nights,
        h.rooms,
        h.check_in_time,
        h.check_out_time,
        h.hotel_per_room_usd,
        s.hotel_discount_amount * h.hotel_per_room_usd AS hotel_per_room_savings_usd,
        f.origin_airport,
        ha.home_airport_lat AS origin_airport_lat,
        ha.home_airport_lon AS origin_airport_lon,
        f.destination_airport,
        f.destination,
        f.seats,
        f.return_flight_booked,
        f.departure_time,
        f.return_time,
        f.checked_bags,
        f.trip_airline,
        f.destination_airport_lat,
        f.destination_airport_lon,
        f.base_fare_usd,
        s.flight_discount_amount * f.base_fare_usd AS flight_fare_savings_usd
    FROM sessions s
    JOIN users u ON s.user_id = u.user_id
    LEFT JOIN flights f ON s.trip_id = f.trip_id
    LEFT JOIN hotels h ON s.trip_id = h.trip_id
    LEFT JOIN home_airports ha ON f.origin_airport = ha.home_airport
  	LEFT JOIN cancelled_trips ct ON s.trip_id = ct.trip_id
  	LEFT JOIN booked_trips bt ON s.trip_id = bt.trip_id
    WHERE
  		-- cohort filter
  		s.user_id IN (SELECT user_id FROM cohort)
      AND s.session_start >= '2023-01-04'
  		-- remove rows with anomalous number of nights
  		AND ((h.check_out_time::date - h.check_in_time::date) is null
           or (h.check_out_time::date - h.check_in_time::date) > 0)
),
unpaired_trips AS (
  select trip_id,
      count (session_id)
  from session_aggregate_stage1 s
  where
  s.trip_id is not null
  AND s.trip_id in (select trip_id from cancelled_trips)
  group by s.trip_id
  having count(s.session_id) = 1
),

session_aggregate_stage2 AS (
    SELECT *,
        CASE WHEN booking_session_date IS NOT NULL AND trip_start_date IS NOT NULL
             THEN trip_start_date::date - booking_session_date::date END AS booking_lead_time_in_days,
        CASE WHEN cancellation_session_date IS NOT NULL AND trip_start_date IS NOT NULL
             THEN trip_start_date::date - cancellation_session_date::date END AS cancellation_lead_time_in_days,
        6371 * 2 * ASIN(
            SQRT(
                POWER(SIN(RADIANS(destination_airport_lat - origin_airport_lat) / 2), 2) +
                COS(RADIANS(origin_airport_lat)) *
                COS(RADIANS(destination_airport_lat)) *
                POWER(SIN(RADIANS(destination_airport_lon - origin_airport_lon) / 2), 2)
            )
        ) AS distance_flown_km
    FROM session_aggregate_stage1
  	-- remove the rows where hotel or flight is booked but there are no hotel/flight details
  	WHERE (flight_booked = false OR trip_airline is not NULL)
  	AND (hotel_booked = false OR hotel_name is not NULL)
    -- remove rows for unpaired trips
  	AND (trip_id is null OR trip_id NOT IN (SELECT trip_id FROM unpaired_trips))
),
session_aggregate AS (
    SELECT *,
        CASE WHEN distance_flown_km >= 4800 THEN true
             WHEN distance_flown_km IS NULL THEN NULL
             ELSE false
        END AS is_longhaul_flight
    FROM session_aggregate_stage2
),
non_bookers AS (
  select s.user_id,
      count (distinct(s.trip_id))
  from session_aggregate s
  group by s.user_id
  having count(s.trip_id) = 0
),
trip_cancellers AS (
 	select s.user_id
  from session_aggregate s
  where trip_is_cancelled = true
),
top_values AS (
    SELECT DISTINCT user_id,
        COALESCE(
          MODE() WITHIN GROUP (ORDER BY trip_airline) FILTER (WHERE flight_booked)
          , 'MISSING') AS top_airline,
        COALESCE(
          MODE() WITHIN GROUP (ORDER BY origin_airport || '-' || destination_airport) FILTER (WHERE flight_booked)
          , 'MISSING') AS top_flight_route,
        COALESCE(
          MODE() WITHIN GROUP (ORDER BY hotel_chain) FILTER (WHERE hotel_booked)
  			  , 'MISSING')AS top_hotel_chain
    FROM session_aggregate
    GROUP BY user_id
),
users_with_at_least_one_flight as (
select user_id,
	count (trip_id) FILTER (WHERE flight_booked AND NOT trip_is_cancelled) as flight_count
FROM  session_aggregate
group by user_id
having count (trip_id) FILTER (WHERE flight_booked AND NOT trip_is_cancelled) > 0
order by count (trip_id) FILTER (WHERE flight_booked AND NOT trip_is_cancelled) desc
),
users_with_exactly_one_flight AS (
SELECT user_id,
  COUNT(DISTINCT trip_id) FILTER (WHERE flight_booked AND NOT cancellation) AS flight_count
  FROM session_aggregate
  GROUP BY user_id
  having COUNT(DISTINCT trip_id) FILTER (WHERE flight_booked AND NOT cancellation) = 1
),
booked_flights_with_discounts AS (
-- all users who booked flights with discounts where the trip is not cancelled
-- if a user is not in this list, it means they either did not book flights at all
-- or they only booked flights without discount
SELECT distinct (user_id) from session_aggregate
  WHERE
  flight_booked = true
  and flight_discount_amount is not null
  and trip_is_cancelled = false
),
booked_flights_ONLY_WITHOUT_discounts AS (
-- all users who booked flights without a discount who did not book any flight WITH a discount
-- i.e. they only ever booked flights at base price
SELECT distinct (user_id) from session_aggregate
  WHERE flight_booked = true
  and flight_discount_amount is null
  and trip_is_cancelled = false
  and user_id not in (select user_id from booked_flights_with_discounts)
),
users_with_at_least_one_hotel as (
select user_id,
	count (trip_id) FILTER (WHERE hotel_booked AND NOT trip_is_cancelled) as hotel_count
FROM  session_aggregate
group by user_id
having count (trip_id) FILTER (WHERE hotel_booked AND NOT trip_is_cancelled) > 0
order by count (trip_id) FILTER (WHERE hotel_booked AND NOT trip_is_cancelled) desc
),
users_with_exactly_one_hotel AS (
SELECT user_id,
  COUNT(DISTINCT trip_id) FILTER (WHERE hotel_booked AND NOT cancellation) AS flight_count
  FROM session_aggregate
  GROUP BY user_id
  having COUNT(DISTINCT trip_id) FILTER (WHERE hotel_booked AND NOT cancellation) = 1
),
booked_hotels_with_discounts AS (
-- all users who booked hotels with discounts where the trip is not cancelled
-- if a user is not in this list, it means they either did not book hotels at all
-- or they only booked hotels without discount
SELECT distinct (user_id) from session_aggregate
  WHERE
  hotel_booked = true
  and hotel_discount_amount is not null
  and trip_is_cancelled = false
),
booked_hotels_ONLY_WITHOUT_discounts AS (
-- all users who booked hotels without a discount who did not book any hotel WITH a discount
-- i.e. they only ever booked hotels at base price
SELECT distinct (user_id) from session_aggregate
  WHERE hotel_booked = true
  and hotel_discount_amount is null
  and trip_is_cancelled = false
  and user_id not in (select user_id from booked_hotels_with_discounts)
),
user_level_aggregate_stage1 AS (
    SELECT
        sa.user_id,
        birthdate,
        age_in_years,
        gender,
        married,
        has_children,
        home_country,
        home_city,
        home_airport,
        home_airport_lat,
        home_airport_lon,
        sign_up_date,
        days_as_customer,

        COUNT(session_id) AS total_sessions,
        AVG(page_clicks) AS avg_clicks_per_session,
        COUNT(*) FILTER (WHERE trip_id IS NOT NULL) * 1.0 / COUNT(*) AS proportion_planning_sessions,
        AVG(session_duration_in_seconds) AS avg_session_duration_seconds,
        COUNT(session_id) * 1.0 / NULLIF(DATE_PART('month', MAX(session_start)) - DATE_PART('month', MIN(session_start)) + 1, 0) AS avg_sessions_per_month,
        DATE_PART('day', '2023-07-28' - MAX(session_start)) AS days_since_last_session,
  			DATE_PART('day', '2023-07-28' - COALESCE(MAX(booking_session_date), '2021-01-01')) AS days_since_last_booking,
        COALESCE(AVG(booking_lead_time_in_days) FILTER (WHERE booking_lead_time_in_days IS NOT NULL), 0) AS avg_booking_lead_time_days,
        COALESCE(AVG(cancellation_lead_time_in_days) FILTER (WHERE cancellation_lead_time_in_days IS NOT NULL),0) AS avg_cancellation_lead_time_days,

        COUNT(DISTINCT trip_id) AS total_trips,
        COUNT(DISTINCT trip_id) FILTER (WHERE flight_booked AND hotel_booked) AS trips_with_flight_and_hotel,
        COALESCE(COUNT(DISTINCT trip_id) FILTER (WHERE flight_booked AND hotel_booked) * 1.0 /
            NULLIF(COUNT(DISTINCT trip_id), 0), 0) AS proportion_trips_with_flight_and_hotel,
        COUNT(DISTINCT trip_id) FILTER (WHERE cancellation) AS total_trips_cancelled,
        COALESCE(COUNT(DISTINCT trip_id) FILTER (WHERE cancellation) * 1.0 /
            NULLIF(COUNT(DISTINCT trip_id), 0), 0) AS trip_cancellation_rate,

  			-- flights
        COUNT(DISTINCT trip_id) FILTER (WHERE flight_booked) AS total_flights,
        COUNT(DISTINCT trip_id) FILTER (WHERE flight_booked AND return_flight_booked) AS flights_with_return,
        COALESCE(COUNT(DISTINCT trip_id) FILTER (WHERE flight_booked AND return_flight_booked) * 1.0 /
            NULLIF(COUNT(DISTINCT trip_id) FILTER (WHERE flight_booked), 0),0) AS proportion_flights_with_return,
        COALESCE(AVG(base_fare_usd) FILTER (WHERE flight_booked AND NOT trip_is_cancelled),0) AS avg_flight_price, -- switch from cancellation
        COALESCE(STDDEV_SAMP(base_fare_usd) FILTER (WHERE flight_booked AND NOT trip_is_cancelled),0) AS stddev_flight_price,
  		  COALESCE(AVG(flight_discount_amount) FILTER (WHERE flight_booked AND flight_discount_amount IS NOT NULL and not cancellation), 0) AS avg_flight_discount_pct,
        COALESCE(AVG(flight_fare_savings_usd) FILTER (WHERE flight_booked AND NOT trip_is_cancelled AND flight_fare_savings_usd IS NOT NULL), 0) AS avg_flight_discount_savings,
  		  COALESCE(SUM(flight_fare_savings_usd) FILTER (WHERE flight_booked AND NOT trip_is_cancelled AND flight_fare_savings_usd IS NOT NULL), 0) AS total_flight_discount_savings,
  		  COALESCE(SUM(base_fare_usd) FILTER (WHERE flight_booked AND NOT trip_is_cancelled) - COALESCE(SUM(flight_fare_savings_usd) FILTER (WHERE flight_booked AND NOT trip_is_cancelled), 0), 0) AS total_flight_spend,
        COUNT(DISTINCT trip_id) FILTER (WHERE flight_booked AND flight_discount) AS flights_with_discount,
        COALESCE(COUNT(DISTINCT trip_id) FILTER (WHERE flight_booked AND flight_discount) * 1.0 /
            NULLIF(COUNT(DISTINCT trip_id) FILTER (WHERE flight_booked), 0),0) AS proportion_flights_with_discount,
        COALESCE(AVG(seats) FILTER (WHERE flight_booked), 0) AS avg_seats_booked,
        COALESCE(STDDEV_SAMP(seats) FILTER (WHERE flight_booked AND NOT cancellation),0) AS stddev_seats,
        COALESCE(AVG(checked_bags) FILTER (WHERE flight_booked AND NOT cancellation), 0) AS avg_bags_checked,
        COALESCE(STDDEV_SAMP(checked_bags) FILTER (WHERE flight_booked AND NOT cancellation),0) AS stddev_checked_bags,
        tv.top_airline,
  			COUNT(DISTINCT trip_airline) FILTER (WHERE flight_booked) AS airline_variety,
        COALESCE(COUNT(DISTINCT trip_id) FILTER (WHERE flight_booked AND trip_airline = tv.top_airline) * 1.0 /
            NULLIF(COUNT(DISTINCT trip_id) FILTER (WHERE flight_booked), 0),0) AS airline_concentration,
        tv.top_flight_route,
        COUNT(DISTINCT origin_airport || '-' || destination_airport) FILTER (WHERE flight_booked) AS flight_route_variety,
        COALESCE(COUNT(DISTINCT trip_id) FILTER (WHERE flight_booked AND origin_airport || '-' || destination_airport = tv.top_flight_route) * 1.0 /
            NULLIF(COUNT(DISTINCT trip_id) FILTER (WHERE flight_booked), 0),0) AS flight_route_concentration,
        COALESCE(AVG(distance_flown_km) FILTER (WHERE flight_booked AND NOT trip_is_cancelled),0) AS avg_distance_flown,
        COALESCE(STDDEV_SAMP(distance_flown_km) FILTER (WHERE flight_booked AND NOT cancellation),0) AS stddev_distance_flown_km,
        COALESCE(COUNT(DISTINCT trip_id) FILTER (WHERE flight_booked AND NOT trip_is_cancelled AND is_longhaul_flight) * 1.0 /
            NULLIF(COUNT(DISTINCT trip_id) FILTER (WHERE flight_booked AND NOT trip_is_cancelled), 0), 0) AS proportion_longhaul_flights,

  			-- hotels
        COUNT(DISTINCT trip_id) FILTER (WHERE hotel_booked) AS total_hotels_booked,
        COALESCE(AVG(hotel_per_room_usd) FILTER (WHERE hotel_booked AND NOT trip_is_cancelled ),0) AS avg_hotel_price_per_room,
  		  COALESCE(STDDEV_SAMP(hotel_per_room_usd) FILTER (WHERE hotel_booked AND NOT trip_is_cancelled),0) AS stddev_hotel_per_room_usd,
  			COUNT(DISTINCT trip_id) FILTER (WHERE hotel_booked AND hotel_discount) AS hotels_with_discount,
  			COALESCE(COUNT(DISTINCT trip_id) FILTER (WHERE hotel_booked AND hotel_discount) * 1.0 /
            NULLIF(COUNT(DISTINCT trip_id) FILTER (WHERE hotel_booked), 0),0) AS proportion_hotels_with_discount,
        COALESCE(AVG(hotel_discount_amount) FILTER (WHERE hotel_booked AND hotel_discount_amount IS NOT NULL AND NOT cancellation), 0) AS avg_hotel_discount_pct,
        COALESCE(AVG(hotel_per_room_savings_usd) FILTER (WHERE hotel_booked AND NOT trip_is_cancelled AND hotel_per_room_savings_usd IS NOT NULL), 0) AS avg_hotel_discount_savings,
  		  COALESCE(SUM(hotel_per_room_savings_usd) FILTER (WHERE hotel_booked AND NOT trip_is_cancelled AND hotel_per_room_savings_usd IS NOT NULL), 0) AS total_hotel_discount_savings,
  		  COALESCE(SUM(hotel_per_room_usd) FILTER (WHERE hotel_booked AND NOT trip_is_cancelled) - COALESCE(SUM(hotel_per_room_savings_usd) FILTER (WHERE hotel_booked AND NOT trip_is_cancelled),0), 0) AS total_hotel_spend,
        COALESCE(AVG(stay_in_nights) FILTER (WHERE hotel_booked AND NOT cancellation),0) AS avg_trip_length_nights,
        COALESCE(STDDEV_SAMP(stay_in_nights) FILTER (WHERE hotel_booked AND NOT cancellation), 0) AS stddev_stay_in_nights,
        COALESCE(AVG(rooms) FILTER (WHERE hotel_booked AND NOT cancellation),0) AS avg_rooms_booked,
  			COALESCE(STDDEV_SAMP(rooms) FILTER (WHERE hotel_booked AND NOT cancellation), 0) AS stddev_rooms,
        tv.top_hotel_chain,
        COUNT(DISTINCT hotel_chain) FILTER (WHERE hotel_booked) AS hotel_chain_variety,
        COALESCE(COUNT(DISTINCT trip_id) FILTER (WHERE hotel_booked AND hotel_chain = tv.top_hotel_chain) * 1.0 /
            NULLIF(COUNT(DISTINCT trip_id) FILTER (WHERE hotel_booked), 0), 0) AS hotel_chain_concentration,

  			-- flags
  			CASE WHEN (sa.user_id in (SELECT user_id from non_bookers)) THEN true else false END as never_booked_trips,
  			CASE WHEN (sa.user_id in (SELECT user_id from trip_cancellers)) THEN false else true END as never_cancelled_trips, --users who are in trip_cancellers cancelled trips at least once
			  CASE WHEN (sa.user_id in (SELECT user_id from users_with_at_least_one_flight)) THEN false else true END as never_booked_flights,
  			CASE WHEN (sa.user_id in (SELECT user_id from users_with_exactly_one_flight)) THEN true else false END as booked_only_one_flight,
			  CASE WHEN (sa.user_id NOT in (SELECT user_id from users_with_at_least_one_flight) -- never booked flights
                  	OR sa.user_id in (select user_id from booked_flights_ONLY_WITHOUT_discounts) -- only booked flights without discounts
                  ) THEN true else false END as never_booked_flights_with_discounts,
  			CASE WHEN (sa.user_id in (SELECT user_id from users_with_at_least_one_hotel)) THEN false else true END as never_booked_hotels,
  			CASE WHEN (sa.user_id in (SELECT user_id from users_with_exactly_one_hotel)) THEN true else false END as booked_only_one_hotel,
  			CASE WHEN (sa.user_id NOT in (SELECT user_id from users_with_at_least_one_hotel) -- never booked hotels
                  	OR sa.user_id in (select user_id from booked_hotels_ONLY_WITHOUT_discounts) -- only booked hotels without discounts
                  ) THEN true else false END as never_booked_hotels_with_discounts

    FROM session_aggregate sa
    JOIN top_values tv ON sa.user_id = tv.user_id
  	GROUP BY sa.user_id, birthdate, age_in_years, gender, married, has_children,
             home_country, home_city, home_airport, home_airport_lat, home_airport_lon,
             sign_up_date, days_as_customer, tv.top_airline, tv.top_flight_route, tv.top_hotel_chain
),
user_level_aggregate AS (
	SELECT *,
  			COALESCE(total_flight_spend,0) + COALESCE(total_hotel_spend,0) as total_spend,
  			COALESCE(total_hotel_discount_savings,0) + COALESCE(total_flight_discount_savings,0) as total_savings
  from user_level_aggregate_stage1
)
SELECT * FROM user_level_aggregate;