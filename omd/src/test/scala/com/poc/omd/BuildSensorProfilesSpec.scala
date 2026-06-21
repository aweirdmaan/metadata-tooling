package com.poc.omd

import org.apache.spark.sql.SparkSession
import org.scalatest.BeforeAndAfterAll
import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers

class BuildSensorProfilesSpec extends AnyFlatSpec with Matchers with BeforeAndAfterAll {

  implicit lazy val spark: SparkSession =
    SparkSession.builder().appName("test").master("local").getOrCreate()

  override def afterAll(): Unit = spark.stop()

  import spark.implicits._

  "aggregate" should "produce one SensorProfile row per sensor with averaged metric_1/metric_2" in {
    val sensor_readings = Seq(
      Reading("sensor_a", 51.1, -0.1, "2024-01-01T00:00:00"),
      Reading("sensor_a", 51.3, -0.3, "2024-01-02T00:00:00"),
      Reading("sensor_b", 52.0,  0.0, "2024-01-01T00:00:00"),
    ).toDS()

    val result = BuildSensorProfiles.aggregate(sensor_readings).collect().sortBy(_.sensor_id)

    result shouldBe Array(
      SensorProfile("sensor_a", avg_metric_1 = 51.2, avg_metric_2 = -0.2, confidence = 2.0 / 100.0),
      SensorProfile("sensor_b", avg_metric_1 = 52.0, avg_metric_2 =  0.0, confidence = 1.0 / 100.0),
    )
  }

  it should "exclude rows with null or empty sensor_id" in {
    val sensor_readings = Seq(
      Reading("sensor_a",  51.0, 0.0, "2024-01-01T00:00:00"),
      Reading("",       51.5, 0.1, "2024-01-01T00:00:00"),
      Reading(null,     51.5, 0.1, "2024-01-01T00:00:00"),
    ).toDS()

    val result = BuildSensorProfiles.aggregate(sensor_readings).collect()

    result shouldBe Array(
      SensorProfile("sensor_a", avg_metric_1 = 51.0, avg_metric_2 = 0.0, confidence = 1.0 / 100.0),
    )
  }

  it should "produce confidence > 1.0 for a high-volume sensor (catches accidental clamp)" in {
    val sensor_readings = (1 to 220).map(i =>
      Reading("sensor_hv", 51.5, -0.1, s"2024-01-01T${i % 24}:00:00")
    ).toDS()

    val result = BuildSensorProfiles.aggregate(sensor_readings).collect()

    result.head.confidence shouldBe >(1.0)
  }
}
