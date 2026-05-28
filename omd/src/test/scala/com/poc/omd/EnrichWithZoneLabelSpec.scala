package com.poc.omd

import org.apache.spark.sql.SparkSession
import org.scalatest.BeforeAndAfterAll
import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers

class EnrichWithZoneLabelSpec extends AnyFlatSpec with Matchers with BeforeAndAfterAll {

  implicit lazy val spark: SparkSession =
    SparkSession.builder().appName("test").master("local").getOrCreate()

  override def afterAll(): Unit = spark.stop()

  import spark.implicits._

  val lookup = Seq(
    ZoneLookup(51, "zone_a"),
    ZoneLookup(52, "zone_b"),
  ).toDS()

  "enrich" should "assign the correct zone_label when avg_metric_1 matches a bucket" in {
    val locations = Seq(
      SensorProfile("sensor_a", 51.5, -0.1, 0.02),
    ).toDS()

    val result = EnrichWithZoneLabel.enrich(locations, lookup).collect()

    result shouldBe Array(EnrichedSensorProfile("sensor_a", 51.5, -0.1, "zone_a"))
  }

  it should "assign zone_label = 'unknown' and preserve the row when no bucket matches" in {
    val locations = Seq(
      SensorProfile("sensor_a", 51.5, -0.1, 0.02),
      SensorProfile("sensor_b", 99.0,  0.0, 0.01),
    ).toDS()

    val result = EnrichWithZoneLabel.enrich(locations, lookup).collect().sortBy(_.sensor_id)

    result.length shouldBe 2
    result(1) shouldBe EnrichedSensorProfile("sensor_b", 99.0, 0.0, "unknown")
  }

  it should "produce the same row count as the input sensor_profiles" in {
    val locations = Seq(
      SensorProfile("sensor_a", 51.5, -0.1, 0.02),
      SensorProfile("sensor_b", 52.3,  0.1, 0.03),
      SensorProfile("sensor_c", 99.0,  0.0, 0.01),
    ).toDS()

    val result = EnrichWithZoneLabel.enrich(locations, lookup).collect()

    result.length shouldBe 3
  }
}
